module Torque
  module PostgreSQL
    module Arel
      class Using < ::Arel::Nodes::Unary
      end

      ::Arel::Nodes::Using = Using
    end
  end
end
