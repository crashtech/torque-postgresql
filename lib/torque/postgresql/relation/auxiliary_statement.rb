module Torque
  module PostgreSQL
    module Relation
      module AuxiliaryStatement

        # :nodoc:
        def auxiliary_statements_values; get_value(:auxiliary_statements); end
        # :nodoc:
        def auxiliary_statements_values=(value); set_value(:auxiliary_statements, value); end

        # Set use of an auxiliary statement already configurated on the model
        def with(*args)
          spawn.with!(*args)
        end

        # Like #with, but modifies relation in place.
        def with!(*args)
          options = args.extract_options!
          args.each do |table|
            instance = table.is_a?(PostgreSQL::AuxiliaryStatement) \
              ? table.class.new(options) \
              : PostgreSQL::AuxiliaryStatement.instantiate(table, self, options)
            instance.ensure_dependencies!(self)
            self.auxiliary_statements_values |= [instance]
          end

          self
        end

        alias_method :auxiliary_statements, :with
        alias_method :auxiliary_statements!, :with!

        # Get all auxiliary statements bound attributes and the base bound
        # attributes as well
        def bound_attributes
          return super unless self.auxiliary_statements_values.present?
          bindings = self.auxiliary_statements_values.map(&:bound_attributes)
          (bindings + super).flatten
        end

        private

          # Hook arel build to add the distinct on clause
          def build_arel
            arel = super
            build_auxiliary_statements(arel)
            arel
          end

          # Build all necessary data for auxiliary statements
          def build_auxiliary_statements(arel)
            return unless self.auxiliary_statements_values.present?

            columns = []
            subqueries = self.auxiliary_statements_values.map do |klass|
              columns << klass.columns
              klass.build_arel(arel, self)
            end

            columns.flatten!
            arel.with(subqueries.flatten)
            arel.project(*columns) if columns.any?
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
