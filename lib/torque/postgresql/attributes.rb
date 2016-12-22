
require_relative 'attributes/type_map'
require_relative 'attributes/composite'
require_relative 'attributes/enum'

module Torque
  module PostgreSQL
    module Attributes
      extend ActiveSupport::Concern

      module ClassMethods
        private

          def define_attribute_method(attribute)
            type = attribute_types[attribute]
            super unless TypeMap.lookup(type, self, attribute)
          end

      end

      def init_with(*)
        instance = super
        aggregate_reflections.each { |name, _| composition_init(name) }
        instance
      end

      private

        # Force a build method if any value was loaded
        def composition_init(name)
          value = _read_attribute(name)
          return if value.nil?
          send("build_#{name}", *value)
        end

    end

    ActiveRecord::Base.include Attributes
  end
end
