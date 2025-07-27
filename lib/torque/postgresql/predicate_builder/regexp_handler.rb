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
          FN.infix(operator, attribute, FN.bind_with(attribute, value.source))
        end

        private
          attr_reader :predicate_builder
      end
    end
  end
end
