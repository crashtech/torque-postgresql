# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module OID
        class EnumSet < Enum
          def initialize(name, enum_klass)
            @name  = name + '[]'
            @klass = Attributes::EnumSet.lookup(name, enum_klass)

            @set_klass = self
            @enum_klass = enum_klass
          end

          def type
            :enum
          end

          def deserialize(value)
            return unless value.present?
            value = value[1..-2].split(',') if value.is_a?(String)
            cast_value(value)
          end

          def serialize(value)
            return if value.blank?
            value = cast_value(value)

            return if value.blank?
            "{#{value.map(&:to_s).join(',')}}"
          end

          # Always use symbol values for schema dumper
          def type_cast_for_schema(value)
            cast_value(value).map(&:to_sym).inspect
          end

          private

            def cast_value(value)
              return if value.blank?
              return value if value.is_a?(@klass)
              @klass.new(value)
            rescue Attributes::EnumSet::EnumSetError
              nil
            end

        end
      end
    end
  end
end
