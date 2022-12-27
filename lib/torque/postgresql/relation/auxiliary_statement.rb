# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Relation
      module AuxiliaryStatement

        # :nodoc:
        def auxiliary_statements_values; get_value(:auxiliary_statements); end
        # :nodoc:
        def auxiliary_statements_values=(value); set_value(:auxiliary_statements, value); end

        # Set use of an auxiliary statement
        def with(*args)
          spawn.with!(*args)
        end

        # Like #with, but modifies relation in place.
        def with!(*args)
          instantiate_auxiliary_statements(*args)
          self
        end

        alias_method :auxiliary_statements, :with
        alias_method :auxiliary_statements!, :with!

        # Get all auxiliary statements bound attributes and the base bound
        # attributes as well
        def bound_attributes
          visitor = ::Arel::Visitors::PostgreSQL.new(ActiveRecord::Base.connection)
          visitor.accept(self.arel.ast, ::Arel::Collectors::Composite.new(
            ::Arel::Collectors::SQLString.new,
            ::Arel::Collectors::Bind.new,
          )).value.last
        end

        private

          # Hook arel build to add the distinct on clause
          def build_arel(*)
            arel = super
            type = auxiliary_statement_type
            subqueries = build_auxiliary_statements(arel)
            subqueries.nil? ? arel : arel.with(*type, *subqueries)
          end

          # Instantiate one or more auxiliary statements for the given +klass+
          def instantiate_auxiliary_statements(*args)
            options = args.extract_options!
            klass = PostgreSQL::AuxiliaryStatement
            klass = klass::Recursive if options.delete(:recursive).present?

            self.auxiliary_statements_values += args.map do |table|
              if table.is_a?(Class) && table < klass
                table.new(options)
              else
                klass.instantiate(table, self, options)
              end
            end
          end

          # Build all necessary data for auxiliary statements
          def build_auxiliary_statements(arel)
            return unless auxiliary_statements_values.present?
            auxiliary_statements_values.map do |klass|
              klass.build(self).tap { arel.join_sources.concat(klass.join_sources) }
            end
          end

          # Return recursive if any auxiliary statement is recursive
          def auxiliary_statement_type
            klass = PostgreSQL::AuxiliaryStatement::Recursive
            :recursive if auxiliary_statements_values.any?(klass)
          end

          # Throw an error showing that an auxiliary statement of the given
          # table name isn't defined
          def auxiliary_statement_error(name)
            raise ArgumentError, <<-MSG.squish
              There's no '#{name}' auxiliary statement defined for #{self.class.name}.
            MSG
          end

      end
    end
  end
end
