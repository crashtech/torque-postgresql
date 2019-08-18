module Torque
  module PostgreSQL
    module Reflection
      module RuntimeReflection
        delegate :klass, :active_record, :connected_through_array?, :macro, :name,
          :build_id_constraint, to: :@reflection
      end

      ::ActiveRecord::Reflection::RuntimeReflection.include(RuntimeReflection)
    end
  end
end
