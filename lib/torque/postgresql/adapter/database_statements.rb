# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module DatabaseStatements

        EXTENDED_DATABASE_TYPES = %i(enum enum_set interval)

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

          query_value(<<-SQL) == 1
            SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = '#{name}'
          SQL
        end

        # Returns true if type exists.
        def type_exists?(name)
          user_defined_types.key? name.to_s
        end
        alias data_type_exists? type_exists?

        # Configure the interval format
        def configure_connection
          super
          execute("SET SESSION IntervalStyle TO 'iso_8601'", 'SCHEMA')
        end

        # Since enums create new types, type map needs to be rebooted to include
        # the new ones, both normal and array one
        def create_enum(name, *)
          super

          oid = query_value("SELECT #{quote(name)}::regtype::oid", "SCHEMA").to_i
          load_additional_types([oid])
        end

        # Change some of the types being mapped
        def initialize_type_map(m = type_map)
          super
          m.register_type 'box',      OID::Box.new
          m.register_type 'circle',   OID::Circle.new
          m.register_type 'interval', OID::Interval.new
          m.register_type 'line',     OID::Line.new
          m.register_type 'segment',  OID::Segment.new

          m.alias_type 'regclass', 'varchar'
        end

        # :nodoc:
        def load_additional_types(oids = nil)
          super
          torque_load_additional_types(oids)
        end

        # Add the composite types to be loaded too.
        def torque_load_additional_types(oids = nil)
          filter = ("AND     a.typelem::integer IN (%s)" % oids.join(', ')) if oids

          query = <<-SQL
            SELECT      a.typelem AS oid, t.typname, t.typelem,
                        t.typdelim, t.typbasetype, t.typtype,
                        t.typarray
            FROM        pg_type t
            INNER JOIN  pg_type a ON (a.oid = t.typarray)
            LEFT JOIN   pg_catalog.pg_namespace n ON n.oid = t.typnamespace
            WHERE       n.nspname NOT IN ('pg_catalog', 'information_schema')
            AND     t.typtype IN ( 'e' )
            #{filter}
            AND     NOT EXISTS(
                      SELECT 1 FROM pg_catalog.pg_type el
                        WHERE el.oid = t.typelem AND el.typarray = t.oid
                      )
            AND     (t.typrelid = 0 OR (
                      SELECT c.relkind = 'c' FROM pg_catalog.pg_class c
                        WHERE c.oid = t.typrelid
                      ))
          SQL

          execute_and_clear(query, 'SCHEMA', []) do |records|
            records.each { |row| OID::Enum.create(row, type_map) }
          end
        end

        # Gets a list of user defined types.
        # You can even choose the +category+ filter
        def user_defined_types(*categories)
          category_condition = categories.present? \
            ? "AND t.typtype IN ('#{categories.join("', '")}')" \
            : "AND t.typtype NOT IN ('b', 'd')"

          select_all(<<-SQL, 'SCHEMA').rows.to_h
            SELECT t.typname AS name,
                   CASE t.typtype
                     WHEN 'e' THEN 'enum'
                     END     AS type
            FROM pg_type t
                   LEFT JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
            WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
              #{category_condition}
              AND NOT EXISTS(
                SELECT 1
                FROM pg_catalog.pg_type el
                WHERE el.oid = t.typelem
                  AND el.typarray = t.oid
              )
              AND (t.typrelid = 0 OR (
              SELECT c.relkind = 'c'
              FROM pg_catalog.pg_class c
              WHERE c.oid = t.typrelid
            ))
            ORDER BY t.typtype DESC
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
          conditions = []
          conditions << <<-SQL if schemas_blacklist.any?
            nspname NOT LIKE ANY (ARRAY['#{schemas_blacklist.join("', '")}'])
          SQL

          conditions << <<-SQL if schemas_whitelist.any?
            nspname LIKE ANY (ARRAY['#{schemas_whitelist.join("', '")}'])
          SQL

          <<-SQL.squish
            SELECT nspname
            FROM pg_catalog.pg_namespace
            WHERE 1=1 AND #{conditions.join(' AND ')}
            ORDER BY oid
          SQL
        end

        # Get the list of columns, and their definition, but only from the
        # actual table, does not include columns that comes from inherited table
        def column_definitions(table_name) # :nodoc:
          # Only affects inheritance
          local_condition = 'AND a.attislocal IS TRUE' if @_dump_mode

          query(<<-SQL, 'SCHEMA')
              SELECT a.attname, format_type(a.atttypid, a.atttypmod),
                     pg_get_expr(d.adbin, d.adrelid), a.attnotnull, a.atttypid, a.atttypmod,
             (SELECT c.collname FROM pg_collation c, pg_type t
               WHERE c.oid = a.attcollation AND t.oid = a.atttypid AND a.attcollation <> t.typcollation),
                     col_description(a.attrelid, a.attnum) AS comment
                FROM pg_attribute a
           LEFT JOIN pg_attrdef d ON a.attrelid = d.adrelid AND a.attnum = d.adnum
               WHERE a.attrelid = '#{quote_table_name(table_name)}'::regclass
                 AND a.attnum > 0
                 AND a.attisdropped IS FALSE
                 #{local_condition}
               ORDER BY a.attnum
          SQL
        end

      end
    end
  end
end
