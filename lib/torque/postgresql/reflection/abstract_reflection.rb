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

        # Fix where the join_scope method is the one now responsible for
        # building the join condition
        def join_scope(table, foreign_table, foreign_klass)
          return super unless connected_through_array?

          table_md = ActiveRecord::TableMetadata.new(klass, table)
          predicate_builder = klass.predicate_builder.with(table_md)
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

          # If we exactly one attribute and one non attribute, then we can take
          # advantage of the ANY operation, which is more cache-friendly
          [klass_attr, source_attr].partition do |item|
            item.is_a?(AREL_ATTR)
          end.then do |attributes, (value, *)|
            if attributes.many? || attributes.first != array_attribute
              attributes.reverse! if klass_type.try(:array?)

              value ||= attributes.pop
              value = ::Arel::Nodes::NamedFunction.new('ANY', Array.wrap(value))
              return attributes.first.eq(value)
            end
          end

          # If the left side is not an array, just use the IN condition
          return klass_attr.in(source_attr) unless klass_type.try(:array)

          # Build the overlap condition (array && array) ensuring that the right
          # side has the same type as the left side
          cast_type = klass_type.sql_type_metadata.sql_type
          source_node = source_attr.is_a?(AREL_NODE)
          source_attr = ::Arel::Nodes.build_quoted(source_attr) unless source_node
          klass_attr.overlaps(source_attr.pg_cast(cast_type))
        end

        # TODO: Deprecate this method
        def join_keys
          OpenStruct.new(key: join_primary_key, foreign_key: join_foreign_key)
        end

        private

          def build_id_constraint_between(table, foreign_table)
            klass_attr  = table[join_primary_key]
            source_attr = foreign_table[join_foreign_key]

            build_id_constraint(klass_attr, source_attr)
          end
      end

      ::ActiveRecord::Reflection::AbstractReflection.prepend(AbstractReflection)
    end
  end
end
