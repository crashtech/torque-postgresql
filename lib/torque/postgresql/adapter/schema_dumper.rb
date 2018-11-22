module Torque
  module PostgreSQL
    module Adapter
      module ColumnDumper

        # Adds +:subtype+ as a valid migration key
        unless Torque::PostgreSQL::AR521
          def migration_keys
            super + [:subtype]
          end
        end

        # Adds +:subtype+ option to the default set
        def prepare_column_options(column)
          spec = super

          if subtype = schema_subtype(column)
            spec[:subtype] = subtype
          end

          spec
        end

        private

          def schema_subtype(column)
            column.sql_type.to_sym.inspect if column.type == :enum
          end

      end
    end
  end
end
