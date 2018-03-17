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
          self.auxiliary_statements ||= {}
          args.each do |table|
            instance = instantiate(table, self, options)
            instance.ensure_dependencies!(self)
            self.auxiliary_statements[table] = instance
          end

          self
        end

        # Get all auxiliary statements bound attributes and the base bound
        # attributes as well
        def bound_attributes
          return super unless self.auxiliary_statements.present?
          bindings = self.auxiliary_statements.values.map(&:bound_attributes)
          (bindings + super).flatten
        end

        private
          delegate :instantiate, to: PostgreSQL::AuxiliaryStatement

          # Hook arel build to add the distinct on clause
          def build_arel
            arel = super

            if self.auxiliary_statements.present?
              columns = []
              subqueries = self.auxiliary_statements.values.map do |klass|
                columns << klass.columns
                klass.build_arel(arel, self)
              end

              arel.with(subqueries.flatten)
              if select_values.empty? && columns.any?
                columns.unshift table[::Arel.star]
                arel.projections = columns
              end
            end

            arel
          end

          # Throw an error showing that an auxiliary statement of the given
          # table name isn't defined
          def auxiliary_statement_error(name)
            raise ArgumentError, <<-MSG.strip
              There's no '#{name}' auxiliary statement defined for #{self.class.name}.
            MSG
          end

      end
    end
  end
end
