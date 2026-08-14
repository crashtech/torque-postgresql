# frozen_string_literal: true

module Torque
  module PostgreSQL
    module PredicateBuilder
      # A condition over an ltree column is rarely a plain equality, so the value
      # decides which operator to use: a plain path is compared with +=+, while
      # anything carrying an lquery marker is matched with +~+
      class LtreeHandler
        class << self
          # An Array is always a single value here, either the labels of a path
          # or the items of a pattern, so it never means a list of values the
          # way the regular handlers would take it. Objects that describe their
          # own path are claimed as well, otherwise a record would be reduced to
          # its primary key before it had the chance to describe itself
          def candidate?(value, type)
            return false unless type.is_a?(Adapter::OID::Ltree)

            value.is_a?(::Array) || value.is_a?(LQuery) ||
              LTree.compatible?(value) || LQuery.marker?(value)
          end
        end

        def initialize(predicate_builder)
          @predicate_builder = predicate_builder
        end

        def call(attribute, type, value)
          return attribute.eq(FN.bind_with(attribute, type.cast(value))) \
            unless LQuery.marker?(value)

          attribute.matches_lquery(pattern_for(attribute, value))
        end

        private

          def pattern_for(attribute, value)
            type = Adapter::OID::Lquery.new
            FN.bind(attribute.name, type.cast(value), type).pg_cast('lquery')
          end
      end
    end
  end
end
