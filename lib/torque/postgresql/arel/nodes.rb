# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Arel
      module Nodes

        class Cast < ::Arel::Nodes::Binary
          include ::Arel::Expressions
          include ::Arel::Predications
          include ::Arel::AliasPredication
          include ::Arel::OrderPredications
          include ::Arel::Math

          def initialize(left, right, array = false)
            right = right.to_s
            right << '[]' if array
            super left, right
          end
        end

      end

      ::Arel.define_singleton_method(:array) do |*values, cast: nil|
        values = values.first if values.size.eql?(1) && values.first.is_a?(::Enumerable)
        result = ::Arel::Nodes.build_quoted(values)
        result = result.cast(cast, true) if cast.present?
        result
      end

      ::Arel::Nodes::Function.include(::Arel::Math)
    end
  end
end
