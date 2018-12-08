module Torque
  module PostgreSQL
    module Adapter
      module OID
        class Enum < ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Enum

          attr_reader :name, :klass

          def self.create(row)
            new(row['typname'])
          end

          def self.auto_initialize?
            Torque::PostgreSQL.config.enum.initializer
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

          # Always use symbol value for schema dumper
          def type_cast_for_schema(value)
            cast_value(value).to_sym.inspect
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
