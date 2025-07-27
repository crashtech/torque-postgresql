# frozen_string_literal: true

module Torque
  module PostgreSQL
    module PredicateBuilder
      class ArelAttributeHandler
        # Shortcut
        def self.call(*args)
          new.call(*args)
        end

        def initialize(*)
          # There is no need to use or save the predicate builder here
        end

        def call(attribute, value)
          case
          when array_typed?(attribute) && array_typed?(value) then attribute.overlaps(value)
          when array_typed?(attribute) then value.eq(FN.any(attribute))
          when array_typed?(value) then attribute.eq(FN.any(value))
          else attribute.eq(value)
          end
        end

        private

          def array_typed?(attribute)
            attribute.able_to_type_cast? && attribute.type_caster.is_a?(ARRAY_OID)
          end
      end
    end
  end
end
