module Torque
  module PostgreSQL
    module Reflection
      module HasManyReflection
        def connected_through_array?
          options[:array]
        end
      end

      ::ActiveRecord::Reflection::HasManyReflection.include(HasManyReflection)
    end
  end
end
