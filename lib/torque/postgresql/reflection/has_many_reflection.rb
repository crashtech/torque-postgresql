# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Reflection
      module HasManyReflection
        def connected_through_array?
          options[:array]
        end

        def array_attribute
          klass.arel_table[foreign_key]
        end
      end

      ::ActiveRecord::Reflection::HasManyReflection.include(HasManyReflection)
    end
  end
end
