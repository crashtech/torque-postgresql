# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module OID
        class StructSet < ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array
          def deserialize(value)
            value.nil? ? [] : super
          end

          def serialize(value)
            return if value.is_a?(::Array) && value.empty?
            super
          end

          def changed_in_place?(raw_old_value, new_value)
            Struct.state(without_backfill.deserialize(raw_old_value)) !=
              Struct.state(new_value)
          end

          def without_backfill
            return self if subtype.backfill.nil?
            @without_backfill ||= self.class.new(subtype.without_backfill, delimiter)
          end

          def empty?(value)
            value.is_a?(::Array) ? value.empty? : subtype.empty?(value)
          end

          def blank_document
            []
          end
        end
      end
    end
  end
end
