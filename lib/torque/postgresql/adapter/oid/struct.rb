
# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module OID
        class Struct < ActiveModel::Type::Value
          attr_reader :name
          include ActiveRecord::ConnectionAdapters::Quoting
          include ActiveRecord::ConnectionAdapters::PostgreSQL::Quoting

          AvailableType = ::Struct.new(:type_map, :name, :oid, :arr_oid, :klass, :array_klass, :registered, keyword_init: true)

          def self.for_type(name)
            typ = _type_by_name(name)
            return nil unless typ

            if !typ.registered
              typ.type_map.register_type(typ.oid,     typ.klass)
              typ.type_map.register_type(typ.arr_oid, typ.array_klass)
              typ.registered = true
            end

            typ.name == name ? typ.klass : typ.array_klass
          end

          def self.register!(type_map, name, oid, arr_oid, klass, array_klass)
            raise ArgumentError, "Already Registered" if _type_by_name(name)
            available_types << AvailableType.new(
              type_map: type_map,
              name: name,
              oid: oid,
              arr_oid: arr_oid,
              klass: klass,
              array_klass: array_klass,
            )
          end

          def self.available_types
            @registry ||= []
          end

          def self._type_by_name(name)
            available_types.find {|a| a.name == name || a.name + '[]' == name}
          end

          def self.create(connection, row, type_map)
            name    = row['typname']
            return if _type_by_name(name)

            oid     = row['oid'].to_i
            arr_oid = row['typarray'].to_i
            type = Struct.new(connection, name)
            arr_type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array.new(type)

            register!(type_map, name, oid, arr_oid, type, arr_type)
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
                col_value = value[col.name]
                serialized = klass.type_for_attribute(col.name).serialize(col_value)
                begin
                  @connection.type_cast(serialized)
                rescue TypeError => e
                  if klass.type_for_attribute(col.name).class == ActiveModel::Type::Value
                    # attribute :nested, NestedStruct.database_type
                    col = klass.columns.find {|c| c.name == col.name }

                    available_custom_type = self.class._type_by_name(col.sql_type)
                    if available_custom_type && !available_custom_type.registered
                      hint = "add `attribute :#{col.name}, #{col.sql_type.classify}.database_#{col.array ? 'array_' : ''}type`"
                      raise e, "#{e} (in #{klass.name}, #{hint}`", $!.backtrace
                    end
                    raise
                  else
                    raise
                  end
                end
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
