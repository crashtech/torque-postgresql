module Torque
  module Postgresql
    module Migration

      module TypesStatements

        EXTENDED_DATABASE_TYPES = {
          enum:      { name: "" },
          composite: { name: "" }
        }

        def self.included(base)
          base.class_eval do
            # Check if a given type is valid.
            def valid_type?(type)
              native_database_types.key?(type) || extended_types.key?(type)
            end
          end
        end

        def extended_types
          EXTENDED_DATABASE_TYPES
        end

        # Gets a list of user defined types.
        # You can even choose the +typcategory+ filter
        def user_defined_types(category = nil)
          category_condition = "AND     typtype = '#{category}'" unless category.nil?
          select_all(<<-SQL).rows.to_h
            SELECT      t.typname AS name,
                        CASE t.typtype
                        WHEN 'e' THEN 'enum'
                        WHEN 'c' THEN 'composite'
                        END AS type
            FROM        pg_type t
            LEFT JOIN   pg_catalog.pg_namespace n ON n.oid = t.typnamespace
            WHERE       n.nspname NOT IN ('pg_catalog', 'information_schema')
            #{category_condition}
            AND     NOT EXISTS(
                      SELECT 1 FROM pg_catalog.pg_type el
                        WHERE el.oid = t.typelem AND el.typarray = t.oid
                      )
            AND     (t.typrelid = 0 OR (
                      SELECT c.relkind = 'c' FROM pg_catalog.pg_class c
                        WHERE c.oid = t.typrelid
                      ))
            ORDER BY    t.typtype DESC
          SQL
        end

        # Returns true if type exists.
        def type_exists?(name)
          user_defined_types.key? name.to_s
        end

        # Drops a type.
        def drop_type(name, options = {})
          force = options.fetch(:force, '').upcase
          check = 'IF EXISTS' if options.fetch(:check, true)
          execute "DROP TYPE #{check} #{quote_type_name(name)} #{force}"
        end

        # Renames a type.
        def rename_type(type_name, new_name)
          execute <<-SQL
            ALTER TYPE #{quote_type_name(type_name)}
            RENAME TO #{quote_type_name(new_name)}
          SQL
        end

      end

      module TypesDumper

        def self.included(base)
          base.class_eval do
            def dump(stream)
              header(stream)
              extensions(stream)
              user_defined_types(stream)
              tables(stream)
              trailer(stream)
              stream
            end
          end
        end

        private

          def user_defined_types(stream)
            types = @connection.user_defined_types
            return unless types.any?

            stream.puts "  # These are user-defined types used on this database"
            types.each do |name, type|
              raise StandardError, "User-defined type '#{name}' cannot be dumped!" if type.blank?
              send(type.to_sym, name, stream)
            end
            stream.puts
          rescue => e
            stream.puts "# Could not dump user-defined types because of following #{e.class}"
            stream.puts "#   #{e.message}"
            stream.puts
          end

      end

      module TypesReversion

        # Records the rename operation for types.
        def rename_type(*args, &block)
          record(:rename_type, args, &block)
        end

        # Inverts the type name.
        def invert_rename_type(args)
          [:rename_type, args.reverse]
        end

      end

      Dumper.send :include, TypesDumper
      Adapter.send :include, TypesStatements
      Reversion.send :include, TypesReversion

    end
  end
end
