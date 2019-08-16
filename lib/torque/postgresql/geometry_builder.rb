module Torque
  module PostgreSQL
    class GeometryBuilder < ActiveModel::Type::Value

      DESTRUCTOR = /[<>{}()]/.freeze
      NUMBER_SERIALIZER = ->(num) { num.to_s.gsub(/\.0$/, '') }

      def type
        return self.class.const_get('TYPE') if self.class.const_defined?('TYPE')
        self.class.const_set('TYPE', self.class.name.demodulize.underscore)
      end

      def pieces
        self.class.const_get('PIECES')
      end

      def formation
        self.class.const_get('FORMATION')
      end

      def cast(value)
        case value
        when ::String
          return if value.blank?
          value.gsub!(DESTRUCTOR, '')
          build_klass(*value.split(','))
        when ::Hash
          build_klass(*value.symbolize_keys.slice(*pieces).values)
        when ::Array
          build_klass(*value)
        else
          value
        end
      end

      def serialize(value)
        parts =
          case value
          when config_class
            pieces.map { |piece| value.public_send(piece) }
          when ::Hash
            value.symbolize_keys.slice(*pieces).values
          when ::Array
            value
          end

        parts = parts&.compact&.flatten
        return if parts.blank?

        raise 'Invalid format' if parts.size < pieces.size
        format(formation, *parts.first(pieces.size).map(&number_serializer))
      end

      def deserialize(value)
        build_klass(*value.gsub(DESTRUCTOR, '').split(',')) unless value.nil?
      end

      def type_cast_for_schema(value)
        if config_class === value
          pieces.map { |piece| value.public_send(piece) }
        else
          super
        end
      end

      def changed_in_place?(raw_old_value, new_value)
        raw_old_value != serialize(new_value)
      end

      protected

        def number_serializer
          self.class.const_get('NUMBER_SERIALIZER')
        end

        def config_class
          Torque::PostgreSQL.config.geometry.public_send("#{type}_class")
        end

        def build_klass(*args)
          return nil if args.empty?
          check_invalid_format!(args)

          config_class.new(*args.try(:first, pieces.size)&.map(&:to_f))
        end

        def check_invalid_format!(args)
          raise 'Invalid format' if args.size < pieces.size
        end
    end
  end
end
