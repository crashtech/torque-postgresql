module Torque
  module PostgreSQL
    module Adapter
      module OID
        class Interval < ActiveModel::Type::Value

          CAST_PARTS = [:years, :months, :days, :hours, :minutes, :seconds]

          def type
            :interval
          end

          # Accepts database-style string, numeric as seconds, array of parts
          # padded to left, or a hash
          #
          # Examples:
          #   [12, 0, 0]
          #   produces: 12 hours, 0 minutes, and 0 seconds
          #
          #   [nil, nil, 3, 0, 0, 0]
          #   produces: 3 days, 0 hours, 0 minutes, and 0 seconds
          #
          #   {minutes: 12, seconds: 0}
          #   produces: 12 minutes, and 0 seconds
          def cast(value)
            return if value.blank?
            case value
            when ::String then deserialize(value)
            when ::ActiveSupport::Duration then value
            when ::Numeric
              parts = CAST_PARTS.map do |part|
                rest, value = value.divmod(1.send(part))
                rest == 0 ? nil : [part, rest]
              end
              parts_to_duration(parts.compact)
            when ::Array
              value.compact!
              parts = CAST_PARTS.drop(6 - value.size).zip(value).to_h
              parts_to_duration(parts)
            when ::Hash
              parts_to_duration(value)
            else
              value
            end
          end

          # Uses the ActiveSupport::Duration::ISO8601Parser
          # See ActiveSupport::Duration#parse
          # The value must be Integer when no precision is given
          def deserialize(value)
            return if value.blank?
            ActiveSupport::Duration.parse(value)
          end

          # Uses the ActiveSupport::Duration::ISO8601Serializer
          # See ActiveSupport::Duration#iso8601
          def serialize(value)
            return if value.blank?
            value = cast(value) unless value.is_a?(ActiveSupport::Duration)
            value = remove_weeks(value) if value.parts.key?(:weeks)
            value.iso8601(precision: @scale)
          end

          # Always use the numeric value for schema dumper
          def type_cast_for_schema(value)
            cast(value).value.inspect
          end

          # Check if the user input has the correct format
          def assert_valid_value(value)
            # TODO: Implement!
          end

          # Transform a list of parts into a duration object
          def parts_to_duration(parts)
            parts = parts.to_h.slice(*CAST_PARTS)
            return 0.seconds if parts.blank?

            seconds = 0
            parts = parts.map do |part, num|
              num = num.to_i unless num.is_a?(Numeric)
              if num > 0
                seconds += num.send(part).value
                [part.to_sym, num]
              end
            end
            ActiveSupport::Duration.new(seconds, parts.compact)
          end

          # As PostgreSQL converts weeks in duration to days, intercept duration
          # values with weeks and turn them into days before serializing so it
          # won't break because the following issues
          # https://github.com/crashtech/torque-postgresql/issues/26
          # https://github.com/rails/rails/issues/34655
          def remove_weeks(value)
            parts = value.parts.dup
            parts[:days] += parts.delete(:weeks) * 7
            ActiveSupport::Duration.new(value.seconds.to_i, parts)
          end
        end
      end
    end
  end
end
