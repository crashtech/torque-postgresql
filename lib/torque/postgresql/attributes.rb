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

        def textxxx
          "Here!"
        end

        private

          # Use local type map to identify attribute decorator
          def define_attribute_method(attribute)
            type = attribute_types[attribute]
            super unless TypeMap.lookup(type, self, attribute, true)
          end

      end
    end

    ActiveRecord::Base.include Attributes
  end
end
