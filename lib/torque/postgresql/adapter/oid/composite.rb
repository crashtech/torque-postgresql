module Torque
  module PostgreSQL
    module Adapter
      module OID
        class Composite < ActiveModel::Type::Value
          include ActiveModel::Type::Helpers::Mutable

          attr_reader :delimiter, :subtypes

          def initialize(subtypes, delimiter = ',')
            @subtypes  = subtypes
            @delimiter = delimiter
            @struct    = create_struct

            @pg_encoder = PG::TextEncoder::Array.new delimiter: delimiter
            @pg_decoder = Coder
          end

          def type
            :composite
          end

          def cast(value)
            result = @struct.dup
            return result if value.blank?

            value = @pg_decoder.decode(value, delimiter) if value.is_a?(::String)

            case value
            when Array
              subtypes.each_with_index do |(name, column), idx|
                result[name] = column.cast(value[idx])
              end
            when Hash
              value.each do |key, part|
                next unless subtypes.key? key.to_s
                result[key] = subtypes[key.to_s].cast(part)
              end
            else
              assert_valid_value(value)
            end

            result
          end

          def serialize(value)
            value = subtypes.map do |name, column|
              column.serialize(value[name])
            end

            return if value.compact.blank?
            @pg_encoder.encode(value).gsub(/\A{(.*)}\Z/m,'(\1)')
          end

          def assert_valid_value(value)
            unless value.blank? || value.is_a?(::Array) || value.is_a?(::Hash) || value.is_a?(::String)
              raise ArgumentError, "'#{value}' is not a valid composite value"
            end
          end

          def ==(other)
            other.is_a?(CompositeOID) &&
              other.subtypes == subtypes
          end

          def type_cast_for_schema(value)
            value.to_h.map! { |name, value| column[name.to_s].type_cast_for_schema(value) }
            "[#{value.join(delimiter)}]"
          end

          def map(value, &block)
            value.map(&block)
          end

          private

            def create_struct
              Struct.new(*subtypes.keys.map(&:to_sym)).new
            end

        end
      end
    end
  end
end
