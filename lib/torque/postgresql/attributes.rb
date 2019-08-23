require_relative 'attributes/lazy'
require_relative 'attributes/builder'

require_relative 'attributes/enum'
require_relative 'attributes/enum_set'
require_relative 'attributes/period'

module Torque
  module PostgreSQL
    module Attributes
      extend ActiveSupport::Concern

      # Configure enum_save_on_bang behavior
      included do
        class_attribute :enum_save_on_bang, instance_accessor: true
        self.enum_save_on_bang = Torque::PostgreSQL.config.enum.save_on_bang
      end
    end

    ActiveRecord::Base.include Attributes
  end
end
