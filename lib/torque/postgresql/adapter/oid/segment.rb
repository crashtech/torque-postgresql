module Torque
  module PostgreSQL
    class Segment < Struct.new(:point0, :point1)
      def x1=(value)
        self.point0 = new_point(value, y1)
      end

      def x1
        point0.x
      end

      def y1=(value)
        self.point0 = new_point(x1, value)
      end

      def y1
        point0.y
      end

      def x2=(value)
        self.point1 = new_point(value, y2)
      end

      def x2
        point1.x
      end

      def y2=(value)
        self.point1 = new_point(x2, value)
      end

      def y2
        point1.y
      end

      private

        def new_point(x, y)
          Torque::PostgreSQL.config.geometry.point_class.new(x, y)
        end
    end

    config.geometry.segment_class ||= ::ActiveRecord.const_set('Segment', Class.new(Segment))

    module Adapter
      module OID
        class Segment < Torque::PostgreSQL::GeometryBuilder

          PIECES = %i[x1 y1 x2 y2].freeze
          FORMATION = '((%s,%s),(%s,%s))'.freeze

          protected

            def point_class
              Torque::PostgreSQL.config.geometry.point_class
            end

            def build_klass(*args)
              return nil if args.empty?
              check_invalid_format!(args)

              x1, y1, x2, y2 = args.try(:first, pieces.size)&.map(&:to_f)
              config_class.new(
                point_class.new(x1, y1),
                point_class.new(x2, y2),
              )
            end

        end
      end
    end
  end
end
