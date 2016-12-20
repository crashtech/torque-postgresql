
require_relative 'attributes/composite'
# require_relative 'adapter/schema_statements'

module Torque
  module PostgreSQL
    module Attributes
      extend ActiveSupport::Concern

      module ClassMethods

        private

          def load_schema!
            super
            klass = self
            attribute_types.each do |name, type|

              case type
              when Torque::PostgreSQL::Adapter::OID::Composite
                decorate_attribute_type(name, :composite) do |subtype|
                  Composite::Decorator.new(type.name, subtype)
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
        @attributes.map do |attribute|
          next unless attribute.type.is_a?(Composite::Decorator)
          attribute.type.bind(self, attribute.name)
        end
        super
      end

    end

    ActiveRecord::Base.send :include, Attributes
  end
end
