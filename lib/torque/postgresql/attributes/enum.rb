module Torque
  module PostgreSQL
    module Attributes
      module Enum
        class EnumError < ArgumentError; end

        class << self

          # Find or create the class that will handle the field
          def lookup(name)
            const     = name.camelize
            namespace = Torque::PostgreSQL.config.enum.namespace

            return namespace.const_get(const) if namespace.const_defined?(const)
            namespace.const_set(const, define_from_type(name))
          end

          # Generate a class to identify enum values specifically by its type
          def define_from_type(name)
            klass = Class.new(Enum)
            klass.instance_variable_set(:@name, name)
            klass
          end

          def connection(name)
            ActiveRecord::Base.connection_handler.retrieve_connection(name)
          end

        end

        class Enum < ActiveSupport::StringInquirer
          include Comparable

          class << self

            # You can specify the connection name for each enum
            def connection_specification_name
              return self == Enum ? 'primary' : superclass.connection_specification_name
            end

            # Load the list of values in a lazy way
            def values
              @values ||= begin
                conn_name = connection_specification_name
                conn = Attributes::Enum.connection(conn_name)
                conn.enum_values(@name)
              end
            end

            # Check if the value is valid
            def valid?(value)
              values.include?(value.to_s)
            end

            # Allow fast creation of values
            def method_missing(method_name, *arguments)
              valid?(method_name) ? new(method_name.to_s) : super
            end

          end

          # Override string initializer to check for a valid value
          def initialize(value)
            raise_invalid(value) unless self.class.valid?(value)
            super
          end

          # Allow comparation between values of the same enum
          def <=>(other)
            raise_comparasion(other) unless other.class == self.class
            to_i <=> other.to_i
          end

          # Get the index of the value
          def to_i
            self.class.values.index(self)
          end

          # It only accepts if the other value is valid
          def replace(value)
            raise_invalid(value) unless self.class.valid?(value)
            super
          end

          # Change the inspection to show the enum name
          def inspect
            "#<#{self.class.name} #{super}>"
          end

          private

            # Allow '_' to be associated to '-'
            def method_missing(method_name, *arguments)
              if method_name[-1] == '?'
                self == method_name[0..-2].tr('_', '-') || super
              elsif method_name[-1] == '!'
                replace(method_name[0..-2])
              else
                super
              end
            end

            # Throw an exception for invalid valus
            def raise_invalid(value)
              raise EnumError, "#{value.inspect} is not valid for #{self.class.name}"
            end

            # Throw an exception for comparasion between different enums
            def raise_comparasion(other)
              raise EnumError, "Comparasion of #{other.class.name} with #{self.class.name} is not allowed"
            end

        end

      end
    end
  end
end
