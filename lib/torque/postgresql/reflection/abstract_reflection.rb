# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Reflection
      module AbstractReflection
        AREL_ATTR = ::Arel::Attributes::Attribute
        AREL_NODE = ::Arel::Nodes::Node

        # Check if the foreign key actually exists
        def connected_through_array?
          false
        end

        # Connection through an array-like attribute is more complex then just
        # a simple eq. This needs to go through the channel that handles larger
        # situations
        def join_scope(table, foreign_table, foreign_klass)
          return super unless connected_through_array?

          table_md = ActiveRecord::TableMetadata.new(klass, table)
          predicate_builder = klass.predicate_builder.with(table_md)
          scope_chain_items = join_scopes(table, predicate_builder)
          klass_scope       = klass_join_scope(table, predicate_builder)

          klass_scope.where!(build_id_constraint_between(table, foreign_table))
          scope_chain_items.inject(klass_scope, &:merge!)
        end

        # Manually build the join constraint
        def build_join_constraint(table, foreign_table)
          result = build_id_constraint_between(table, foreign_table)
          result = table.create_and([result, klass.send(:type_condition, table)]) \
            if klass.finder_needs_type_condition?

          result
        end

        private

          # This one is a lot simpler, now that we have a predicate builder that
          # knows exactly what to do with 2 array-like attributes
          def build_id_constraint_between(table, foreign_table)
            PredicateBuilder::ArelAttributeHandler.call(
              table[join_primary_key],
              foreign_table[join_foreign_key],
            )
          end
      end

      ::ActiveRecord::Reflection::AbstractReflection.prepend(AbstractReflection)
    end
  end
end
