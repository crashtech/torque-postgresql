
require_relative 'attributes/type_map'
require_relative 'attributes/bindable'
require_relative 'attributes/composite'
# require_relative 'adapter/enum'

module Torque
  module PostgreSQL
    module Attributes
      # extend ActiveSupport::Concern

      # module ClassMethods

      #   # def define_attribute_method(attr_name)
      #   #   super unless TypeMap.lookup(attribute_types[attr_name], self, attr_name)
      #   # end
      #   # define_method_attribute
      #   # define_method_attribute=

      # end

      # def _read_attribute(attr_name)
      #   return value unless (value = super).nil?
      # end

    end

    ActiveRecord::Base.include Attributes
  end
end
