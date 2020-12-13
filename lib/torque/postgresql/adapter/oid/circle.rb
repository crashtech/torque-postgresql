# frozen_string_literal: true

module Torque
  module PostgreSQL
    class Circle < Struct.new(:x, :y, :r)
      alias radius r
      alias radius= r=

      def center
        point_class.new(x, y)
      end

      def center=(value)
        parts = value.is_a?(point_class) ? [value.x, value.y] : value[0..1]
        self.x = parts.first
        self.y = parts.last
      end

      private

        def point_class
          Torque::PostgreSQL.config.geometry.point_class
        end
    end

    config.geometry.circle_class ||= ::ActiveRecord.const_set('Circle', Class.new(Circle))

    module Adapter
      module OID
        class Circle < Torque::PostgreSQL::GeometryBuilder

          PIECES = %i[x y r].freeze
          FORMATION = '<(%s,%s),%s>'.freeze

        end
      end
    end
  end
end
