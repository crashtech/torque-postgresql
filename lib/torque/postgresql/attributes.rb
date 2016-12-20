
require_relative 'attributes/composite'
# require_relative 'adapter/schema_statements'

module Torque
  module PostgreSQL
    module Attributes
      extend ActiveSupport::Concern

      module ClassMethods

        attr_accessor :composite_decorators

        private

          def load_schema!
            super
            klass = self
            klass.composite_decorators = {}
            attribute_types.each do |name, type|

              case type
              when Torque::PostgreSQL::Adapter::OID::Composite
                decorate_attribute_type(name, :composite) do |subtype|
                  klass.composite_decorators[name] = Composite::Decorator.new(type.name, subtype)
                end
              when ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Enum
                enum_values = ActiveSupport::HashWithIndifferentAccess.new
                decorate_attribute_type(name, :enum) do |subtype|
                  ActiveRecord::Enum::EnumType.new(name, enum_values, subtype)
                end
              else
                super
              end

            end
          end

      end

      # Bind this instance to any composite types
      def init_internals
        return super unless self.class.composite_decorators
        self.class.composite_decorators.each { |name, type| type.bind(self, name) }
        super
      end

    end

    ActiveRecord::Base.send :include, Attributes
  end
end
