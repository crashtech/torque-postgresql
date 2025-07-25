# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Associations
      module AssociationScope

        module ClassMethods
          def get_bind_values(*)
            super.flatten
          end
        end

        private

          # When the relation is connected through an array, intercept the
          # condition builder and uses an overlap condition building it on
          # +build_id_constraint+
          def last_chain_scope(scope, reflection, owner)
            return super unless reflection.connected_through_array?

            keys = reflection.join_keys
            value = transform_value(owner[keys.foreign_key])
            constraint = build_id_constraint(reflection, keys, value, true)

            scope.where!(constraint)
          end

          # When the relation is connected through an array, intercept the
          # condition builder and uses an overlap condition building it on
          # +build_id_constraint+
          def next_chain_scope(scope, reflection, next_reflection)
            return super unless reflection.connected_through_array?

            keys = reflection.join_keys
            foreign_table = next_reflection.aliased_table

            value = foreign_table[keys.foreign_key]
            constraint = build_id_constraint(reflection, keys, value)

            scope.joins!(join(foreign_table, constraint))
          end

          # Trigger the same method on the relation which will build the
          # constraint condition using array logics
          def build_id_constraint(reflection, keys, value, bind_param = false)
            table = reflection.aliased_table

            if bind_param
              source_attr = reflection.array_attribute
              value = ::Arel::Nodes.build_quoted(Array.wrap(value), source_attr)
              value = build_bind_param_for_constraint(
                reflection,
                value.value_for_database,
                source_attr.name,
              )
            end

            reflection.build_id_constraint(table[keys.key], value)
          end

          # For array-like values, it needs to call the method as many times as
          # the array size
          def transform_value(value)
            if value.is_a?(::Enumerable)
              value.map { |v| value_transformation.call(v) }
            else
              value_transformation.call(value)
            end
          end

          def build_bind_param_for_constraint(reflection, value, foreign_key)
            ::Arel::Nodes::BindParam.new(::ActiveRecord::Relation::QueryAttribute.new(
              foreign_key, value, reflection.klass.attribute_types[foreign_key],
            ))
          end
      end

      ::ActiveRecord::Associations::AssociationScope.singleton_class.prepend(AssociationScope::ClassMethods)
      ::ActiveRecord::Associations::AssociationScope.prepend(AssociationScope)
    end
  end
end
