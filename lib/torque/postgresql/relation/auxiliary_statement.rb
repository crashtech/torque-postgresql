module Torque
  module PostgreSQL
    module Relation
      module AuxiliaryStatement

        attr_accessor :auxiliary_statements

        # Set use of an auxiliary statement already configurated on the model
        def with(*args)
          spawn.with!(*args)
        end

        # Like #with, but modifies relation in place.
        def with!(*args)
          options = args.extract_options!
          self.auxiliary_statements ||= []
          args.each do |table|
            unless self.auxiliary_statements_list.key?(table)
              raise ArgumentError, <<-MSG.gsub(/^ +| +$|\n/, '')
                There's no '#{table}' auxiliary statement defined for #{self.class.name}.
              MSG
            end

            klass = self.auxiliary_statements_list[table]
            self.auxiliary_statements << klass.new(options)
          end
          self
        end

        private

          # Hook arel build to add the distinct on clause
          def build_arel
            arel = super

            if self.auxiliary_statements.present?
              columns = []
              subqueries = self.auxiliary_statements.map do |klass|
                columns << klass.columns
                klass.build_arel(arel)
              end

              arel.with(subqueries)
              if select_values.empty? && columns.any?
                columns.unshift table[Arel.sql('*')]
                arel.projections = columns
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
