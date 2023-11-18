# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Relation
      module AuxiliaryStatement

        # :nodoc:
        def auxiliary_statements_values; get_value(:auxiliary_statements); end
        # :nodoc:
        def auxiliary_statements_values=(value); set_value(:auxiliary_statements, value); end

        # Hook into the +from+ method to allow querying from a CTE
        def from(value, subquery_name = nil, **options)
          if value.is_a?(Symbol) && auxiliary_statements_list.key?(value)
            value = auxiliary_statements_list[value]
            value = value.new(**options)
          end

          super(value, subquery_name)
        end

        # Set use of an auxiliary statement
        def with(*args, **settings)
          spawn.with!(*args, **settings)
        end

        # Like #with, but modifies relation in place.
        def with!(*args, **settings)
          instantiate_auxiliary_statements(*args, **settings)
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
            # Check if CTE was included as part of the from of the query
            from = from_clause.value
            from_cte = from.is_a?(PostgreSQL::AuxiliaryStatement)

            # Build the arel normally and then get the type of the statements
            arel = super
            type = auxiliary_statement_type

            # Build all the statements and add them to the arel
            sub_queries = build_auxiliary_statements(arel).flatten
            sub_queries << from.build(self, false) if from_cte
            arel.with(*type, *sub_queries) unless sub_queries.empty?
            arel
          end

          # Intercept when the FROM clause is being generated to properly build
          # from a setup CTE
          def build_from
            opts = from_clause.value
            return super unless opts.is_a?(PostgreSQL::AuxiliaryStatement)

            name = from_clause.name
            name ? opts.table.as(name.to_s) : opts.table_name
          end

          # Instantiate one or more auxiliary statements for the given +klass+
          def instantiate_auxiliary_statements(*args, **options)
            klass = PostgreSQL::AuxiliaryStatement
            klass = klass::Recursive if options.delete(:recursive).present?

            self.auxiliary_statements_values += args.map do |table|
              if table.is_a?(Class) && table < klass
                table.new(**options)
              else
                klass.instantiate(table, self, **options)
              end
            end
          end

          # Build all necessary data for auxiliary statements
          def build_auxiliary_statements(arel)
            return [] unless auxiliary_statements_values.present?
            auxiliary_statements_values.map do |klass|
              klass.build(self).tap { arel.join_sources.concat(klass.join_sources) }
            end
          end

          # Return recursive if any auxiliary statement is recursive
          def auxiliary_statement_type
            klass = PostgreSQL::AuxiliaryStatement::Recursive
            :recursive if auxiliary_statements_values.any?(klass) ||
              from_clause.value.is_a?(klass)
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
