require_relative 'attributes/type_map'
require_relative 'attributes/lazy'

require_relative 'attributes/builder'

require_relative 'attributes/enum'

module Torque
  module PostgreSQL
    module Attributes
      extend ActiveSupport::Concern

      # Configure enum_save_on_bang behavior
      included do
        class_attribute :enum_save_on_bang, instance_accessor: true
        self.enum_save_on_bang = Torque::PostgreSQL.config.enum.save_on_bang
      end

      module ClassMethods

        private

          # If the attributes are not loaded,
          def method_missing(method_name, *args, &block)
            return super unless define_attribute_methods
            self.send(method_name, *args, &block)
          end

          # Use local type map to identify attribute decorator
          def define_attribute_method(attribute)
            type = attribute_types[attribute]
            super unless TypeMap.lookup(type, self, attribute)
          end

      end
    end

    ActiveRecord::Base.include Attributes
  end
end
