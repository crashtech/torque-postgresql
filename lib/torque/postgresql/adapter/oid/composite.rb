module Torque
  module PostgreSQL
    module Adapter
      module OID
        class Composite < ActiveModel::Type::Value
          include ActiveModel::Type::Helpers::Mutable

          attr_reader :delimiter, :name

          def initialize(name, delimiter = ',')
            @name      = name
            @delimiter = delimiter

            @pg_encoder = Coder
            @pg_decoder = Coder
          end

          def type
            :composite
          end

          def cast(value)
            return if value.blank?

            assert_valid_value(value)
            value = @pg_decoder.decode(value) if value.is_a?(::String)
            value
          end

          def serialize(value)
            return if value.compact.blank?
            @pg_encoder.encode(Coder::Record.new(value))
          end

          def assert_valid_value(value)
            unless value.blank? || value.is_a?(::Array) || value.is_a?(::Hash) || value.is_a?(::String)
              raise ArgumentError, "'#{value}' is not a valid composite value"
            end
          end

          def ==(other)
            other.is_a?(Composite) &&
              other.name == name
          end

          def map(value, &block)
            value.map(&block)
          end

          def hash
            [self.class, name].hash
          end

        end
      end
    end
  end
end
