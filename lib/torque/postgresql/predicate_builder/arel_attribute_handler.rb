# frozen_string_literal: true

module Torque
  module PostgreSQL
    module PredicateBuilder
      class ArelAttributeHandler
        def initialize(predicate_builder)
          @predicate_builder = predicate_builder
        end

        def call(attribute, value)
          case
          when array_typed?(attribute) && array_typed?(value) then attribute.overlaps(value)
          when array_typed?(attribute) then value.eq(any_function(attribute))
          when array_typed?(value) then attribute.eq(any_function(value))
          else attribute.eq(value)
          end
        end

        private
          attr_reader :predicate_builder

          def any_function(value)
            ::Arel::Nodes::NamedFunction.new('ANY', [value])
          end

          def array_typed?(attribute)
            attribute.type_caster.is_a?(ARRAY_OID)
          end
      end
    end
  end
end
