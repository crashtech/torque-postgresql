module Torque
  module PostgreSQL
    class Box < Struct.new(:x1, :y1, :x2, :y2)
      def points
        klass = Torque::PostgreSQL.config.geometry.point_class
        [
          klass.new(x1, y1),
          klass.new(x1, y2),
          klass.new(x2, y1),
          klass.new(x2, y2),
        ]
      end
    end

    config.geometry.box_class ||= ::ActiveRecord.const_set('Box', Class.new(Box))

    module Adapter
      module OID
        class Box < Torque::PostgreSQL::GeometryBuilder

          PIECES = %i[x1 y1 x2 y2].freeze
          FORMATION = '((%s,%s),(%s,%s))'.freeze

        end
      end
    end
  end
end
