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

        # Translate +:enum_set+ into +:enum+
        def schema_type(column)
          if column.type == :enum_set
            :enum
          else
            super
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
            column.sql_type.to_sym.inspect if column.type == :enum || column.type == :enum_set
          end

      end
    end
  end
end
