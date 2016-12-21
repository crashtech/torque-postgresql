
require_relative 'attributes/type_map'
require_relative 'attributes/composite'
# require_relative 'adapter/enum'

module Torque
  module PostgreSQL
    module Attributes
      extend ActiveSupport::Concern

      module ClassMethods
        private

          def inherited(subclass)
            subclass.class_eval do
              decorate_name = :_additional_decorators
              matcher = ->(name, type) { TypeMap.present?(type) }
              decorate_matching_attribute_types(matcher, decorate_name) do |subtype|
                TypeMap.lookup(subtype)
              end
            end
            super
          end

      end

    end

    ActiveRecord::Base.include Attributes
  end
end
