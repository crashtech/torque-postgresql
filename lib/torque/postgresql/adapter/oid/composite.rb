# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module OID
        class Composite < ActiveModel::Type::Value
          ARRAY = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array
          DATA = ARRAY::Data

          attr_reader :name

          # The composite type behind the given type, if there is one, wrapped
          # or not by an array
          def self.from(type)
            type = type.subtype if type.is_a?(ARRAY)
            type if type.is_a?(self)
          end

          def self.create(row, type_map)
            oid_klass = new(row['typname'])
            type_map.register_type(row['oid'].to_i, oid_klass)
            type_map.register_type(row['typarray'].to_i, ARRAY.new(oid_klass, row['typdelim']))
          end

          def initialize(name)
            @name = name.to_s.freeze
          end

          # The class that represents the composite type, loaded in a lazy way
          def klass
            @klass ||= Attributes::Composite.lookup(name)
          end

          # The ordered list of columns of the composite type, as a hash of
          # name and type
          def columns
            klass.columns
          end

          def type
            :composite
          end

          def cast(value)
            case value
            when klass then value
            when ::Hash then build(value)
            when DATA then deserialize(value)
            when ::String then deserialize(value)
            when ::Array then build(columns.keys.zip(value).to_h)
            else value
            end
          end

          # A record that was already serialized comes back as the encoder and
          # its values, which is how it is kept around for dirty tracking
          def deserialize(value)
            return if value.nil?

            fields = value.is_a?(DATA) ? value.values : decoder.decode(value)
            instance = klass.new
            set = attributes_of(instance)

            columns.each_key.with_index do |attr_name, idx|
              set.write_from_database(attr_name, fields[idx])
            end

            instance
          end

          # The record is handed over to the adapter as an encoder and its
          # values, the same way arrays are, so that columns are type casted by
          # the connection right before the record literal is built. Values come
          # from the record itself, so that types declared by the class, like
          # encrypted ones, are the ones being applied
          def serialize(value)
            return if value.nil?

            set = attributes_of(cast(value))
            values = columns.each_key.map { |attr_name| set[attr_name].value_for_database }

            DATA.new(encoder, values)
          end

          def changed_in_place?(raw_old_value, new_value)
            deserialize(raw_old_value) != new_value
          end

          def ==(other)
            other.class == self.class && other.name == name
          end
          alias eql? ==

          def hash
            [self.class, name].hash
          end

          private

            def build(attrs)
              klass.new(**attrs.symbolize_keys)
            end

            def attributes_of(record)
              record.instance_variable_get(:@attributes)
            end

            def encoder
              @encoder ||= PG::TextEncoder::Record.new
            end

            def decoder
              @decoder ||= PG::TextDecoder::Record.new
            end
        end
      end
    end
  end
end
