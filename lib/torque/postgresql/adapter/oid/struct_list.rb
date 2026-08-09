# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module OID
        class StructList < Struct
          def cast(value)
            case value
            when ::String then cast(parse(value))
            when ::Array then value.map { |item| super(item) }
            else value
            end
          end

          def deserialize(value)
            ::Array.wrap(parse(value)).map do |item|
              build(item, from_database: true, blank: true)
            end
          end

          def serialize(value)
            case value
            when ::Array then value.empty? ? nil : encode(value)
            when nil then nil
            else super
            end
          end

          def empty?(value)
            value.is_a?(::Array) ? value.empty? : super
          end

          def blank_document
            []
          end

          private

            def encode(items)
              hashes = items.map { |item| item.is_a?(klass) ? document(item) : item }
              ActiveSupport::JSON.encode(hashes)
            end
        end
      end
    end
  end
end
