module Torque
  module PostgreSQL
    module Relation
      module AuxiliaryStatement

        attr_accessor :auxiliary_statements

        # Set use of an auxiliary statement already configurated on the model
        def with(*list)
          spawn.with!(*list)
        end

        # Like #with, but modifies relation in place.
        def with!(*list)
          self.auxiliary_statements ||= []
          self.auxiliary_statements += list
          self
        end

        private

          # Hook arel build to add the distinct on clause
          def build_arel
            arel = super

            if self.auxiliary_statements.present?
              columns = []
              subqueries = self.auxiliary_statements.map do |table|
                auxiliary_statement_error(table) unless auxiliary_statements_list.key?(table)
                auxiliary_statements_list[table].build_arel(arel, columns)
              end

              arel.with(subqueries)
              if select_values.empty? && columns.any?
                arel.projections = [table[Arel.sql('*')]]
                arel.project *columns
              end
            end

            arel
          end

          # Throw an error showing that an auxiliary statement of the given
          # table name isn't defined
          def auxiliary_statement_error(name)
            raise ArgumentError, <<-MSG.gsub(/^ +| +$|\n/, '')
              There's no '#{name}' auxiliary statement defined for
              #{self.class.name}.
            MSG
          end

      end
    end
  end
end
