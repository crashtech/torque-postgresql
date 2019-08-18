module Torque
  module PostgreSQL
    module Adapter
      module OID
        class Range < ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Range
          HASH_PICK = %i[from start end to].freeze

          module Comparasion
            def <=>(other)
              return super unless other.acts_like?(:date) || other.acts_like?(:time)
              other = other.to_time if other.acts_like?(:date)
              super other.to_i
            end
          end

          def cast_value(value)
            case value
            when Array
              cast_custom(value[0], value[1])
            when Hash
              pieces = value.with_indifferent_access.values_at(*HASH_PICK)
              cast_custom(pieces[0] || pieces[1], pieces[2] || pieces[3])
            else
              super
            end
          end

          private

            def cast_custom(from, to)
              from = custom_cast_single(from, true)
              to = custom_cast_single(to)
              ::Range.new(from, to)
            end

            def custom_cast_single(value, negative = false)
              value.blank? ? custom_infinity(negative) : subtype.deserialize(value)
            end

            def custom_infinity(negative)
              negative ? -::Float::INFINITY : ::Float::INFINITY
            end
        end

        ::ActiveRecord::ConnectionAdapters::PostgreSQL::OID.send(:remove_const, :Range)
        ::ActiveRecord::ConnectionAdapters::PostgreSQL::OID.const_set(:Range, Range)

        ::Float.prepend(Range::Comparasion)
      end
    end
  end
end
