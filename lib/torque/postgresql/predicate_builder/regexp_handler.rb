# frozen_string_literal: true

module Torque
  module PostgreSQL
    module PredicateBuilder
      class RegexpHandler
        def initialize(predicate_builder)
          @predicate_builder = predicate_builder
        end

        def call(attribute, value)
          operator = value.casefold? ? :"~*" : :"~"
          bind = predicate_builder.build_bind_attribute(attribute.name, value.source)
          build_node(operator, attribute, bind)
        end

        private
          attr_reader :predicate_builder

          def build_node(*args)
            ::Arel::Nodes::InfixOperation.new(*args)
          end
      end
    end
  end
end
