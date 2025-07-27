# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Associations
      module AssociationScope
        # A customized predicate builder for array attributes that can be used
        # standalone and changes the behavior of the blank state
        class PredicateBuilderArray
          include PredicateBuilder::ArrayHandler

          def call_with_empty(attribute)
            '1=0' # Does not match records with empty arrays
          end
        end

        module ClassMethods
          def get_bind_values(*)
            super.flatten
          end
        end

        private

          # When loading a join by value (last as in we know which records to
          # load) only has many array need to have a different behavior, so it
          # can properly match array values
          def last_chain_scope(scope, reflection, owner)
            return super unless reflection.connected_through_array?
            return super if reflection.macro == :belongs_to_many

            constraint = PredicateBuilderArray.new.call_for_array(
              reflection.array_attribute,
              transform_value(owner[reflection.join_foreign_key]),
            )

            scope.where!(constraint)
          end

          # When loading a join by reference (next as in we don't know which
          # records to load), it can take advantage of the new predicate builder
          # to figure out the most optimal way to connect both properties
          def next_chain_scope(scope, reflection, next_reflection)
            return super unless reflection.connected_through_array?

            primary_key = reflection.aliased_table[reflection.join_primary_key]
            foreign_key = next_reflection.aliased_table[reflection.join_foreign_key]
            constraint = PredicateBuilder::ArelAttributeHandler.call(primary_key, foreign_key)

            scope.joins!(join(foreign_table, constraint))
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
      end

      ::ActiveRecord::Associations::AssociationScope.singleton_class.prepend(AssociationScope::ClassMethods)
      ::ActiveRecord::Associations::AssociationScope.prepend(AssociationScope)
    end
  end
end
