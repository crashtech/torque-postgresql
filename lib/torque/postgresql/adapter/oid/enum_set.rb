module Torque
  module PostgreSQL
    module Adapter
      module OID
        class EnumSet < Enum

          attr_reader :enum_klass

          def initialize(name, enum_klass)
            @name  = name + '[]'
            @klass = Attributes::EnumSet.lookup(name, enum_klass)
            @enum_klass = enum_klass
          end

          def type
            :enum_set
          end

          def serialize(value)
            return if value.blank?
            value = cast_value(value)
            value.map(&:to_s) unless value.blank?
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
            rescue Attributes::EnumSet::EnumError
              nil
            end

        end
      end
    end
  end
end
