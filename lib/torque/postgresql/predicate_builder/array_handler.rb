# frozen_string_literal: true

module Torque
  module PostgreSQL
    module PredicateBuilder
      module ArrayHandler
        def call(attribute, value)
          return super unless array_attribute?(attribute) &&
            PostgreSQL.config.predicate_builder.handle_array_attributes

          call_for_array(attribute, value)
        end

        def call_for_array(attribute, value)
          if !value.is_a?(::Array)
            call_with_value(attribute, value)
          elsif value.any?
            call_with_array(attribute, value)
          else
            call_with_empty(attribute)
          end
        end

        private

          def call_with_value(attribute, value)
            left = predicate_builder.build_bind_attribute(attribute.name, value)
            right = ::Arel::Nodes::NamedFunction.new('ANY', [attribute])
            ::Arel::Nodes::Equality.new(left, right)
          end

          def call_with_array(attribute, value)
            bind = predicate_builder.build_bind_attribute(attribute.name, value)
            attribute.overlaps(bind)
          end

          def call_with_empty(attribute)
            ::Arel::Nodes::NamedFunction.new('CARDINALITY', [attribute]).eq(0)
          end

          def array_attribute?(attribute)
            attribute.type_caster.is_a?(ARRAY_OID)
          end
      end

      ::ActiveRecord::PredicateBuilder::ArrayHandler.prepend(ArrayHandler)
      ::ActiveRecord::PredicateBuilder::BasicObjectHandler.prepend(ArrayHandler)
    end
  end
end
