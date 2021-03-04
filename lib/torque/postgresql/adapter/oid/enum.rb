# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module OID
        class Enum < ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Enum

          attr_reader :name, :klass, :set_klass, :enum_klass

          # Delegate all Hash-like methods to the enum class
          delegate *(Array.public_instance_methods - Object.public_methods), to: :@klass

          def self.create(row, type_map)
            name    = row['typname']
            oid     = row['oid'].to_i
            arr_oid = row['typarray'].to_i

            oid_klass     = Enum.new(name)
            oid_set_klass = EnumSet.new(name, oid_klass.klass)
            oid_klass.instance_variable_set(:@set_klass, oid_set_klass)

            type_map.register_type(oid,     oid_klass)
            type_map.register_type(arr_oid, oid_set_klass)
          end

          def initialize(name)
            @name  = name
            @klass = Attributes::Enum.lookup(name)

            @enum_klass = self
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

          def ==(other)
            self.class == other.class &&
              other.klass == klass &&
              other.type == type
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
