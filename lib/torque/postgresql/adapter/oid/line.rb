# frozen_string_literal: true

module Torque
  module PostgreSQL
    class Line < Struct.new(:slope, :intercept)
      alias c intercept
      alias c= intercept=

      def a=(value)
        self.slope = vertical? \
          ? Float::INFINITY \
          : Rational(value, b)
      end

      def a
        slope.numerator
      end

      def b=(value)
        self.slope = value.zero? \
          ? Float::INFINITY \
          : Rational(a, value)
      end

      def b
        vertical? ? 0 : slope.denominator
      end

      def horizontal?
        slope.zero?
      end

      def vertical?
        !slope.try(:infinite?).eql?(nil)
      end
    end

    config.geometry.line_class ||= ::ActiveRecord.const_set('Line', Class.new(Line))

    module Adapter
      module OID
        class Line < Torque::PostgreSQL::GeometryBuilder

          PIECES = %i[a b c].freeze
          FORMATION = '{%s,%s,%s}'.freeze

          protected

            def build_klass(*args)
              return nil if args.empty?
              check_invalid_format!(args)

              a, b, c = args.try(:first, pieces.size)&.map(&:to_f)
              slope = b.zero? ? Float::INFINITY : Rational(a, b)
              config_class.new(slope, c)
            end
        end
      end
    end
  end
end
