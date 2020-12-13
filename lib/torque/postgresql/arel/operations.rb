# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Arel
      module Operations

        # Create a cast operation
        def cast(type, array = false)
          Nodes::Cast.new(self, type, array)
        end

      end

      ::Arel::Attributes::Attribute.include(Operations)
      ::Arel::Nodes::SqlLiteral.include(Operations)
      ::Arel::Nodes::Node.include(Operations)
    end
  end
end
