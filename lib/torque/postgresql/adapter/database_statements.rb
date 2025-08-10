# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module DatabaseStatements

        EXTENDED_DATABASE_TYPES = %i[enum enum_set interval]

        # Switch between dump mode or not
        def dump_mode!
          @_dump_mode = !!!@_dump_mode
        end

        # List of schemas blocked by the application in the current connection
        def schemas_blacklist
          @schemas_blacklist ||= Torque::PostgreSQL.config.schemas.blacklist +
            (@config.dig(:schemas, 'blacklist') || [])
        end

        # List of schemas used by the application in the current connection
        def schemas_whitelist
          @schemas_whitelist ||= Torque::PostgreSQL.config.schemas.whitelist +
            (@config.dig(:schemas, 'whitelist') || [])
        end

        # A list of schemas on the search path sanitized
        def schemas_search_path_sanitized
          @schemas_search_path_sanitized ||= begin
            db_user = @config[:username] || ENV['USER'] || ENV['USERNAME']
            schema_search_path.split(',').map { |item| item.strip.sub('"$user"', db_user) }
          end
        end

        # Check if a given type is valid.
        def valid_type?(type)
          super || extended_types.include?(type)
        end

        # Get the list of extended types
        def extended_types
          EXTENDED_DATABASE_TYPES
        end

        # Checks if a given schema exists in the database. If +filtered+ is
        # given as false, then it will check regardless of whitelist and
        # blacklist
        def schema_exists?(name, filtered: true)
          return user_defined_schemas.include?(name.to_s) if filtered

          query_value(<<-SQL, "SCHEMA") == 1
            SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = #{quote(name)}
          SQL
        end

        # Returns true if type exists.
        def type_exists?(name)
          user_defined_types.key? name.to_s
        end
        alias data_type_exists? type_exists?

        # Change some of the types being mapped
        def initialize_type_map(m = type_map)
          super

          if PostgreSQL.config.geometry.enabled
            m.register_type 'box',      OID::Box.new
            m.register_type 'circle',   OID::Circle.new
            m.register_type 'line',     OID::Line.new
            m.register_type 'segment',  OID::Segment.new
          end

          if PostgreSQL.config.interval.enabled
            m.register_type 'interval', OID::Interval.new
          end
        end

        # :nodoc:
        def load_additional_types(oids = nil)
          type_map.alias_type 'regclass', 'varchar'
          type_map.alias_type 'regconfig', 'varchar'
          super
          torque_load_additional_types(oids)
        end

        # Add the composite types to be loaded too.
        def torque_load_additional_types(oids = nil)
          return unless torque_load_additional_types?

          # Types: (b)ase, (c)omposite, (d)omain, (e)num, (p)seudotype, (r)ange
          # (m)ultirange

          query = <<~SQL
            SELECT t.oid, t.typname, t.typelem, t.typdelim, t.typinput,
                   r.rngsubtype, t.typtype, t.typbasetype, t.typarray
            FROM pg_type as t
            LEFT JOIN pg_range as r ON oid = rngtypid
            LEFT JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
            WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
          SQL

          if oids
            query += " AND t.oid IN (%s)" % oids.join(", ")
          else
            query += " AND t.typtype IN ('e')"
          end

          options = { allow_retry: true, materialize_transactions: false }
          internal_execute(query, 'SCHEMA', **options).each do |row|
            if row['typtype'] == 'e' && PostgreSQL.config.enum.enabled
              OID::Enum.create(row, type_map)
            end
          end
        end

        def torque_load_additional_types?
          PostgreSQL.config.enum.enabled
        end

        # Gets a list of user defined types.
        # You can even choose the +category+ filter
        def user_defined_types(*categories)
          categories = categories.compact.presence || %w[c e p r m]

          query(<<-SQL, 'SCHEMA').to_h
            SELECT t.typname, t.typtype
            FROM pg_type as t
            LEFT JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
            WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
            AND t.typtype IN ('#{categories.join("', '")}')
          SQL
        end

        # Get the list of inherited tables associated with their parent tables
        def inherited_tables
          tables = query(<<-SQL, 'SCHEMA')
            SELECT inhrelid::regclass  AS table_name,
                   inhparent::regclass AS inheritances
            FROM pg_inherits
            JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
            JOIN pg_class child  ON pg_inherits.inhrelid  = child.oid
            ORDER BY inhrelid
          SQL

          tables.each_with_object({}) do |(child, parent), result|
            (result[child] ||= []) << parent
          end
        end

        # Get the list of schemas that were created by the user
        def user_defined_schemas
          query_values(user_defined_schemas_sql, 'SCHEMA')
        end

        # Build the query for allowed schemas
        def user_defined_schemas_sql
          <<-SQL.squish
            SELECT nspname
            FROM pg_catalog.pg_namespace
            WHERE 1=1 AND #{filter_by_schema.join(' AND ')}
            ORDER BY oid
          SQL
        end

        # Get the list of columns, and their definition, but only from the
        # actual table, does not include columns that comes from inherited table
        def column_definitions(table_name)
          query(<<~SQL, "SCHEMA")
              SELECT a.attname, format_type(a.atttypid, a.atttypmod),
                     pg_get_expr(d.adbin, d.adrelid), a.attnotnull, a.atttypid, a.atttypmod,
                     c.collname, col_description(a.attrelid, a.attnum) AS comment,
                     #{supports_identity_columns? ? 'attidentity' : quote('')} AS identity,
                     #{supports_virtual_columns? ? 'attgenerated' : quote('')} as attgenerated
                FROM pg_attribute a
                LEFT JOIN pg_attrdef d ON a.attrelid = d.adrelid AND a.attnum = d.adnum
                LEFT JOIN pg_type t ON a.atttypid = t.oid
                LEFT JOIN pg_collation c ON a.attcollation = c.oid AND a.attcollation <> t.typcollation
               WHERE a.attrelid = #{quote(quote_table_name(table_name))}::regclass
                 AND a.attnum > 0 AND NOT a.attisdropped
                 #{'AND a.attislocal' if @_dump_mode}
               ORDER BY a.attnum
          SQL
        end

        # Get all possible schema entries that can be created via versioned
        # commands of the provided type. Mostly for covering removals and not
        # dump them
        def list_versioned_commands(type)
          query =
            case type
            when :function
              <<-SQL.squish
                SELECT n.nspname AS schema, p.proname AS name
                FROM pg_catalog.pg_proc p
                INNER JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE 1=1 AND #{filter_by_schema.join(' AND ')};
              SQL
            when :type
              <<-SQL.squish
                SELECT n.nspname AS schema, t.typname AS name
                FROM pg_type t
                INNER JOIN pg_namespace n ON n.oid = t.typnamespace
                WHERE 1=1 AND t.typtype NOT IN ('e')
                  AND #{filter_by_schema.join(' AND ')};
              SQL
            when :view
              <<-SQL.squish
                SELECT n.nspname AS schema, c.relname AS name
                FROM pg_class c
                INNER JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE 1=1 AND c.relkind IN ('v', 'm')
                  AND #{filter_by_schema.join(' AND ')};
              SQL
            end

          select_rows(query, 'SCHEMA')
        end

        # Build the condition for filtering by schema
        def filter_by_schema
          conditions = []
          conditions << <<-SQL.squish if schemas_blacklist.any?
            nspname NOT LIKE ALL (ARRAY['#{schemas_blacklist.join("', '")}'])
          SQL

          conditions << <<-SQL.squish if schemas_whitelist.any?
            nspname LIKE ANY (ARRAY['#{schemas_whitelist.join("', '")}'])
          SQL
          conditions
        end

      end
    end
  end
end
