module Torque
  module PostgreSQL
    module Reflection
      module ThroughReflection
        delegate :build_id_constraint, :connected_through_array?, to: :source_reflection
      end

      ::ActiveRecord::Reflection::ThroughReflection.include(ThroughReflection)
    end
  end
end
