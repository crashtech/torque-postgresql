# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Arel
      module Operations

        # Create a cast operation
        def pg_cast(type, array = false)
          Nodes::Cast.new(self, type, array)
        end

        # Make sure to add proper support over AR's own +cast+ method while
        # still allow attributes to be casted
        def cast(type, array = false)
          defined?(super) && !array ? super(type) : pg_cast(type, array)
        end

      end

      ::Arel::Attributes::Attribute.include(Operations)
      ::Arel::Nodes::SqlLiteral.include(Operations)
      ::Arel::Nodes::Node.include(Operations)
    end
  end
end
