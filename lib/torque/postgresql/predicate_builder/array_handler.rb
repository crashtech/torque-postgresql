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
          return attribute.eq(nil) if value.nil?

          value = value.to_a if value.is_a?(::Set)
          return call_with_value(attribute, value) unless value.is_a?(::Array)
          return call_with_empty(attribute) if value.empty?

          nils, values = value.map { |entry| id_of(entry) }.partition(&:nil?)
          return attribute.eq(nil) if values.empty?

          condition = call_with_array(attribute, values)
          nils.empty? ? condition : condition.or(attribute.eq(nil))
        end

        private

          def call_with_value(attribute, value)
            FN.infix(:"=", FN.bind_with(attribute, value), FN.any(attribute))
          end

          def call_with_array(attribute, value)
            attribute.overlaps(FN.bind_with(attribute, value))
          end

          def call_with_empty(attribute)
            FN.cardinality(attribute).eq(0)
          end

          def id_of(entry)
            entry.is_a?(::ActiveRecord::Base) ? entry.id : entry
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
