
# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module OID
        class Struct < ActiveModel::Type::Value
          attr_reader :name
          include ActiveRecord::ConnectionAdapters::Quoting
          include ActiveRecord::ConnectionAdapters::PostgreSQL::Quoting

          def self.create(connection, row, type_map)
            name    = row['typname']
            oid     = row['oid'].to_i
            arr_oid = row['typarray'].to_i
            type = Struct.new(connection, name)
            type_map.register_type(oid,     type)
            type_map.register_type(arr_oid, ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array.new(type))
          end

          def initialize(connection, name)
            @connection = connection # The connection we're attached to
            @name = name

            @pg_encoder = PG::TextEncoder::Record.new name: name
            @pg_decoder = PG::TextDecoder::Record.new name: name
            super()
          end

          def deserialize(value)
            return unless value.present?
            return super(value) unless klass
            return value if value.is_a? klass
            fields = PG::TextDecoder::Record.new.decode(value)
            field_names = klass.columns.map(&:name)
            attributes = Hash[field_names.zip(fields)]
            field_names.each { |field| attributes[field] = klass.type_for_attribute(field).deserialize(attributes[field]) }
            build_from_attrs(attributes)
          end

          def serialize(value)
            return if value.blank?
            return super(value) unless klass
            value = cast_value(value)
            if value.nil?
              "NULL"
            else
              casted_values = klass.columns.map do |col|
                @connection.type_cast(klass.type_for_attribute(col.name).serialize(value[col.name]))
              end
              PG::TextEncoder::Record.new.encode(casted_values)
            end
          end

          def assert_valid_value(value)
            cast_value(value)
          end

          def type_cast_for_schema(value)
            # TODO: Check default values for struct types work
            serialize(value)
          end

          def ==(other)
            self.class == other.class &&
              other.klass == klass &&
              other.type == type
          end

          def klass
            @klass ||= validate_klass(name.to_s.camelize.singularize) || validate_klass(name.to_s.camelize.pluralize)
            return nil unless @klass
            if @klass.ancestors.include?(::ActiveRecord::Base)
              return @klass if @klass.table_name == name
            end
            return nil unless @klass.ancestors.include?(::Torque::Struct)
            @klass
          end

          def type_cast(value)
            value
          end

          private

            def validate_klass(class_name)
              klass = class_name.safe_constantize
              if klass && klass.ancestors.include?(::Torque::Struct)
                klass
              elsif klass && klass.ancestors.include?(::ActiveRecord::Base)
                klass.table_name == name ? klass : nil
              else
                false
              end
            end

            def cast_value(value)
              return if value.blank?
              return if klass.blank?
              return value if value.is_a?(klass)
              build_from_attrs(value)
            end

            def build_from_attrs(attributes)
              attributes = klass.attributes_builder.build_from_database(attributes, {})
              klass.allocate.init_with_attributes(attributes)
            end

        end
      end
    end
  end
end
