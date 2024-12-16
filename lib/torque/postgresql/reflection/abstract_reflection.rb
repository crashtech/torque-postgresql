# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Reflection
      module AbstractReflection
        AREL_ATTR = ::Arel::Attributes::Attribute

        ARR_NO_CAST = 'bigint'
        ARR_CAST = 'bigint[]'

        # Check if the foreign key actually exists
        def connected_through_array?
          false
        end

        # Fix where the join_scope method is the one now responsible for
        # building the join condition
        def join_scope(table, foreign_table, foreign_klass)
          return super unless connected_through_array?

          predicate_builder = predicate_builder(table)
          scope_chain_items = join_scopes(table, predicate_builder)
          klass_scope       = klass_join_scope(table, predicate_builder)

          klass_scope.where!(build_id_constraint_between(table, foreign_table))
          klass_scope.where!(type => foreign_klass.polymorphic_name) if type
          klass_scope.where!(klass.send(:type_condition, table)) \
            if klass.finder_needs_type_condition?

          scope_chain_items.inject(klass_scope, &:merge!)
        end

        # Manually build the join constraint
        def build_join_constraint(table, foreign_table)
          result = build_id_constraint_between(table, foreign_table)
          result = table.create_and([result, klass.send(:type_condition, table)]) \
            if klass.finder_needs_type_condition?

          result
        end

        # Build the id constraint checking if both types are perfect matching.
        # The klass attribute (left side) will always be a column attribute
        def build_id_constraint(klass_attr, source_attr)
          return klass_attr.eq(source_attr) unless connected_through_array?

          # Klass and key are associated with the reflection Class
          klass_type = klass.columns_hash[join_keys.key.to_s]

          # Apply an ANY operation which checks if the single value on the left
          # side exists in the array on the right side
          if source_attr.is_a?(AREL_ATTR)
            any_value = [klass_attr, source_attr]
            any_value.reverse! if klass_type.try(:array?)
            return any_value.shift.eq(::Arel::Nodes::NamedFunction.new('ANY', any_value))
          end

          # If the left side is not an array, just use the IN condition
          return klass_attr.in(source_attr) unless klass_type.try(:array)

          # Build the overlap condition (array && array) ensuring that the right
          # side has the same type as the left side
          source_attr = ::Arel::Nodes.build_quoted(Array.wrap(source_attr))
          klass_attr.overlaps(source_attr.cast(klass_type.sql_type_metadata.sql_type))
        end

        # TODO: Deprecate this method
        def join_keys
          KeyAndForeignKey.new(key: join_primary_key, foreign_key: join_foreign_key)
        end

        private

          def build_id_constraint_between(table, foreign_table)
            klass_attr  = table[join_primary_key]
            source_attr = foreign_table[join_foreign_key]

            build_id_constraint(klass_attr, source_attr)
          end
      end

      KeyAndForeignKey = Struct.new(:key, :foreign_key, keyword_init: true)

      ::ActiveRecord::Reflection::AbstractReflection.prepend(AbstractReflection)
    end
  end
end
