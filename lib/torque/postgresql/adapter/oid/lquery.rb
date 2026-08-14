# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module OID
        class Lquery < ActiveModel::Type::Value

          def type
            :lquery
          end

          def cast(value)
            return if value.blank?
            return value if value.is_a?(LQuery)

            LQuery.new(value)
          end

          def deserialize(value)
            return if value.nil?

            LQuery.load(value)
          end

          def serialize(value)
            cast(value)&.to_s
          end

          def type_cast_for_schema(value)
            cast(value).to_s.inspect
          end

          def changed_in_place?(raw_old_value, new_value)
            raw_old_value != serialize(new_value)
          end

          # Types resolved through the type map are deduplicated and frozen, so
          # they need to be comparable
          def ==(other)
            other.is_a?(self.class)
          end
          alias eql? ==

          def hash
            self.class.hash
          end

        end
      end
    end
  end
end
