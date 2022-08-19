# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Associations
      module Preloader
        module LoaderQuery
          def foreign_column
            @foreign_column ||= scope.columns_hash[association_key_name.to_s]
          end

          def load_records_for_keys(keys, &block)
            condition = query_condition_for(keys)
            scope.where(condition).load(&block)
          end

          def query_condition_for(keys)
            if connected_through_array?
              value = scope.cast_for_condition(foreign_column, keys.to_a)
              scope.table[association_key_name].overlaps(value)
            else
              { association_key_name => keys }
            end
          end

          def connected_through_array?
            foreign_column.array?
          end
        end

        ::ActiveRecord::Associations::Preloader::Association::LoaderQuery
          .prepend(LoaderQuery)
      end
    end
  end
end
