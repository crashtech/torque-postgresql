module Torque
  module PostgreSQL
    module Adapter
      module OID
        class Composite < ActiveModel::Type::Value

          attr_reader :delimiter, :name

          def initialize(name, delimiter = ',')
            @name      = name
            @delimiter = delimiter

            @pg_encoder = Coder
            @pg_decoder = Coder
          end

          def type
            :composite
          end

          def serialize(value)
            return if (value = cast_value(value)).blank?
            @pg_encoder.encode(Coder::Record.new(value))
          end

          def changed_in_place?(raw_old_value, new_value)
            raw_old_value != serialize(new_value)
          end

          def ==(other)
            other.is_a?(Composite) &&
              other.name == name
          end

          def map(value, &block)
            value.map(&block)
          end

          def hash
            [self.class, name].hash
          end

          private

            def cast_value(value)
              case value
              when ::Array              then value
              when ::Hash               then value.values
              when ::String             then @pg_decoder.decode(value)
              when ::ActiveRecord::Base then value.attributes.values
              else nil
              end
            end

        end
      end
    end
  end
end
