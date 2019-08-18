module Torque
  module PostgreSQL
    module Arel
      module Nodes

        class Cast < ::Arel::Nodes::Binary
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
    end
  end
end
