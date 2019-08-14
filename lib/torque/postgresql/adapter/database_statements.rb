module Torque
  module PostgreSQL
    module Adapter
      module DatabaseStatements

        EXTENDED_DATABASE_TYPES = %i(enum enum_set interval)

        # Switch between dump mode or not
        def dump_mode!
          @_dump_mode = !!!@_dump_mode
        end

        # Check if a given type is valid.
        def valid_type?(type)
          super || extended_types.include?(type)
        end

        # Get the list of extended types
        def extended_types
          EXTENDED_DATABASE_TYPES
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

        # Change some of the types being mapped
        def initialize_type_map(m = type_map)
          super
          m.register_type 'box', OID::Box.new
          m.register_type 'circle', OID::Circle.new
          m.register_type 'interval', OID::Interval.new
          m.register_type 'line', OID::Line.new
          m.register_type 'segment', OID::Segment.new
        end

        # :nodoc:
        if Torque::PostgreSQL::AR521
          def load_additional_types(oids = nil)
            super
            torque_load_additional_types(oids)
          end
        else
          def load_additional_types(type_map, oids = nil)
            super
            torque_load_additional_types(oids)
          end
        end

        # Add the composite types to be loaded too.
        def torque_load_additional_types(oids = nil)
          filter = "AND     a.typelem::integer IN (%s)" % oids.join(", ") if oids

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
            records.each do |row|
              case row['typtype']
              when 'e' then OID::Enum.create(row, type_map)
              end
            end
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
            SELECT child.relname             AS table_name,
                   array_agg(parent.relname) AS inheritances
            FROM pg_inherits
            JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
            JOIN pg_class child  ON pg_inherits.inhrelid  = child.oid
            GROUP BY child.relname, pg_inherits.inhrelid
            ORDER BY pg_inherits.inhrelid
          SQL

          tables.map do |(table, refs)|
            [table, Coder.decode(refs)]
          end.to_h
        end

        # Get the list of columns, and their definition, but only from the
        # actual table, does not include columns that comes from inherited table
        def column_definitions(table_name) # :nodoc:
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

        # Extracts the value from a PostgreSQL column default definition.
        def extract_value_from_default(default)
          case default
            # Array elements
          when /\AARRAY\[(.*)\]\z/
            # TODO: Improve this since it's not the most safe approach
            eval(default.gsub(/ARRAY|::\w+(\[\])?/, ''))
          else
            super
          end
        rescue SyntaxError
          # If somethin goes wrong with the eval, just return nil
        end

      end
    end
  end
end
