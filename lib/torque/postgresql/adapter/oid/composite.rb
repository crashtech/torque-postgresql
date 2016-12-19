module Torque
  module PostgreSQL
    module Adapter
      module OID
        class Composite < ActiveModel::Type::Value
          attr_reader :delimiter, :subtypes

          # TODO Use Struct in place of OpenStruct
          def initialize(subtypes, delimiter = ',')
            @subtypes  = subtypes
            @delimiter = delimiter
            @struct    = create_struct

            # It uses the array encoder because the strcuture is the same
            @pg_encoder = PG::TextEncoder::Array.new delimiter: delimiter
          end

          def type
            :composite
          end

          def cast(value)
            result = @struct.dup
            return result if value.blank?

            if value.is_a?(::String)
              value = value.gsub(/\A\((.*)\)\Z/m,'\1')
              value = value.split(delimiter, -1).map(&method(:unescape))
            end

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

          def changed_in_place?(raw_old_value, new_value)
            cast(raw_old_value) != new_value
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
              OpenStruct.new(subtypes.map { |name, _| [name, nil] }.to_h)
            end

            def unescape(value)
              # There's an issue with double quotes, the database always saves it duplicated, but
              # never brings back with a single quoute
              value.gsub(/\A"(.*)"\Z/m, '\1').gsub(/""/m, '"')
            end

        end
      end
    end
  end
end
