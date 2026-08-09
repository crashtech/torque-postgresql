# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module OID
        class Struct < ActiveRecord::Type::Json
          attr_reader :klass, :type, :backfill

          # A comparable representation of a struct-backed value, based on the
          # values it exposes instead of the document it generates, so that
          # non-deterministic types like encrypted attributes stay stable
          def self.state(value)
            case value
            when nil then nil
            when ::Array then value.map { |item| state(item) }
            else value.respond_to?(:attributes) ? [value.class, value.attributes] : value
            end
          end

          def initialize(klass, type: :jsonb, backfill: nil)
            super()
            @klass = klass
            @type = type
            @backfill = backfill
          end

          def cast(value)
            case value
            when klass then value
            when ::Hash then build(value)
            when ::String then cast(parse(value))
            else value
            end
          end

          def deserialize(value)
            build(parse(value), from_database: true, blank: true)
          end

          def serialize(value)
            case value
            when klass then empty?(value) ? nil : super(document(value))
            when nil then nil
            else super
            end
          end

          def changed?(old_value, new_value, _new_value_before_cast)
            Struct.state(old_value) != Struct.state(new_value)
          end

          def changed_in_place?(raw_old_value, new_value)
            Struct.state(without_backfill.deserialize(raw_old_value)) != Struct.state(new_value)
          end

          # The same type, but reading documents exactly as they are stored, so
          # that backfilled properties are seen as changes
          def without_backfill
            return self if backfill.nil?
            @without_backfill ||= self.class.new(klass, type: type)
          end

          def empty?(value)
            document(value).empty?
          end

          # The hash that represents the value on the database, holding only the
          # properties that were actually written to it
          def document(value)
            set = value.instance_variable_get(:@attributes)
            set.keys.to_h { |name| [name, set[name].value_for_database] }
          end

          def blank_document
            {}
          end

          def ==(other)
            other.class == self.class && other.klass == klass && other.type == type
          end
          alias eql? ==

          def hash
            [self.class, klass, type].hash
          end

          private

            def parse(value)
              return value unless value.is_a?(::String)
              ActiveSupport::JSON.decode(value) rescue nil
            end

            def build(data, from_database: false, blank: false)
              instance = klass.new
              blank!(instance) if blank
              return instance unless data.is_a?(::Hash)

              from_database ? load(instance, data) : instance.assign_attributes(data)
              instance
            end

            # Reset the instance to the state of an empty document, keeping the
            # class-level defaults that were marked to be backfilled
            def blank!(instance)
              return if backfill == true

              keep = ::Array.wrap(backfill).map(&:to_s)
              set = instance.instance_variable_get(:@attributes).map do |attribute|
                next attribute if keep.include?(attribute.name)
                ActiveModel::Attribute.uninitialized(attribute.name, attribute.type)
              end

              instance.instance_variable_set(:@attributes, set)
            end

            # Properties that the class doesn't declare are kept as they are
            # stored, regardless of the class being strict about them or not
            def load(instance, data)
              default = ActiveModel::Type.default_value
              set = instance.instance_variable_get(:@attributes)

              data.each do |key, value|
                if klass.attribute_names.include?(key = key.to_s)
                  set.write_from_database(key, value)
                else
                  set[key] = ActiveModel::Attribute.from_database(key, value, default)
                end
              end
            end
        end
      end
    end
  end
end
