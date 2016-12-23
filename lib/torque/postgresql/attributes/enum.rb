module Torque
  module PostgreSQL
    module Attributes
      class Enum < String
        include Comparable

        class EnumError < ArgumentError; end

        class << self

          # Find or create the class that will handle the value
          def lookup(name)
            const     = name.camelize
            namespace = Torque::PostgreSQL.config.enum.namespace

            return namespace.const_get(const) if namespace.const_defined?(const)
            namespace.const_set(const, define_from_type(name))
          end

          # You can specify the connection name for each enum
          def connection_specification_name
            return self == Enum ? 'primary' : superclass.connection_specification_name
          end

          # Overpass new so blank values return only nil
          def new(value)
            super unless value.blank?
          end

          # Load the list of values in a lazy way
          def values
            @values ||= self == Enum ? nil : begin
              conn_name = connection_specification_name
              conn = connection(conn_name)
              conn.enum_values(@name)
            end
          end

          # Check if the value is valid
          def valid?(value)
            return false if self == Enum
            self.values.include?(value.to_s)
          end

          private

            # Allows checking value existance
            def respond_to_missing?(method_name, include_private = false)
              valid?(method_name)
            end

            # Allow fast creation of values
            def method_missing(method_name, *arguments)
              return super if self == Enum
              self.valid?(method_name) ? new(method_name.to_s) : super
            end

            # Generate a class to identify enum values specifically by its type
            def define_from_type(name)
              klass = Class.new(Enum)
              klass.instance_variable_set(:@name, name)
              klass
            end

            # Get a connection based on its name
            def connection(name)
              ActiveRecord::Base.connection_handler.retrieve_connection(name)
            end

        end

        # Override string initializer to check for a valid value
        def initialize(value)
          str_value = value.is_a?(Numeric) ? self.class.values[value.to_i] : value
          raise_invalid(value) unless self.class.valid?(str_value)
          super(str_value)
        end

        # Allow comparison between values of the same enum
        def <=>(other)
          raise_comparison(other) if other.is_a?(Enum) && other.class != self.class

          case other
          when Numeric, Enum then to_i <=> other.to_i
          when String        then to_i <=> self.class.values.index(other)
          else raise_comparison(other)
          end
        end

        # Only allow value comparison with values of the same class
        def ==(other)
          (self <=> other) == 0
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

          # Check for valid '?' and '!' methods
          def respond_to_missing?(method_name, include_private = false)
            return true if method_name[-1] == '?'
            method_name[-1] == '!' && self.class.valid?(method_name[0..-2])
          end

          # Allow '_' to be associated to '-'
          def method_missing(method_name, *arguments)
            if method_name[-1] == '?'
              self == method_name[0..-2].tr('_', '-') || self == method_name[0..-2]
            elsif method_name[-1] == '!'
              replace(method_name[0..-2])
            else
              super
            end
          end

          # Throw an exception for invalid valus
          def raise_invalid(value)
            if value.is_a?(Numeric)
              raise EnumError, "#{value.inspect} is out of bounds of #{self.class.name}"
            else
              raise EnumError, "#{value.inspect} is not valid for #{self.class.name}"
            end
          end

          # Throw an exception for comparasion between different enums
          def raise_comparison(other)
            raise EnumError, "Comparison of #{other.class.name} with #{self.class.name} is not allowed"
          end

      end
    end
  end
end
