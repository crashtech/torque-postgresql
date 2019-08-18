require_relative 'reflection/abstract_reflection'
require_relative 'reflection/association_reflection'
require_relative 'reflection/belongs_to_many_reflection'
require_relative 'reflection/has_many_reflection'
require_relative 'reflection/runtime_reflection'
require_relative 'reflection/through_reflection'

module Torque
  module PostgreSQL
    module Reflection

      def create(macro, name, scope, options, ar)
        return super unless macro.eql?(:belongs_to_many)
        BelongsToManyReflection.new(name, scope, options, ar)
      end

    end

    ::ActiveRecord::Reflection.singleton_class.prepend(Reflection)
  end
end
