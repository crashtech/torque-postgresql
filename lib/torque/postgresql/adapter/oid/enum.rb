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
            value = cast_value(value) unless value.is_a?(@klass)
            value.to_i
          end

          def assert_valid_value(value)
            cast_value(value)
          end

          private

            def cast_value(value)
              return if value.blank?
              @klass.new(value)
            end

        end
      end
    end
  end
end
