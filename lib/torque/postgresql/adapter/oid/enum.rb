module Torque
  module PostgreSQL
    module Adapter
      module OID
        class Enum < ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Enum

          def self.create(row)
            new(row['typname'])
          end

          def initialize(name)
            @name  = name
            @klass = Attributes::Enum.lookup(name)
          end

          def hash
            [self.class, name].hash
          end

          def serialize(value)
            return if value.blank?
            value = cast_value(value)
            value.to_s unless value.nil?
          end

          def assert_valid_value(value)
            cast_value(value)
          end

          private

            def cast_value(value)
              return if value.blank?
              return value if value.is_a?(@klass)
              @klass.new(value)
            rescue Attributes::Enum::EnumError
              nil
            end

        end
      end
    end
  end
end
