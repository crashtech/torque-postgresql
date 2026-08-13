# frozen_string_literal: true

require_relative 'simple_enum'

module Torque
  module PostgreSQL
    module Attributes
      # The common ground between the classes that back a column with a set of
      # typed properties, like structs and composite types. It carries enough of
      # the ActiveRecord attribute surface for its own features, and for the
      # ActiveRecord concerns that build on top of it, to work
      class Base
        include ActiveModel::Model
        include ActiveModel::Attributes
        include ActiveModel::Serialization
        include ActiveModel::Serializers::JSON
        include ActiveModel::Dirty
        include ActiveModel::Validations::Callbacks

        include SimpleEnum
        include ActiveRecord::Store
        # Rails 8.1 moved normalization to Active Model, which is where these
        # classes belong anyway
        include(AR810 ? ActiveModel::Attributes::Normalization : ActiveRecord::Normalization)
        include ActiveRecord::Encryption::EncryptableRecord

        class << self
          # These classes are not backed by a table, so nothing here has the
          # extra information that a column would provide
          def columns_hash
            {}
          end

          # Encrypt individual attributes, so their values are stored encrypted
          # inside the column that holds them
          def encrypts(*names, **options)
            names.each do |name|
              raise ArgumentError, <<~MSG.squish unless attribute_names.include?(name.to_s)
                Unable to encrypt "#{name}" because it is not a declared
                attribute of #{self.name}.
              MSG
            end

            super
          end
        end

        # Plain access to any property, declared or not
        def [](key)
          key = key.to_s
          @attributes.key?(key) ? @attributes.fetch_value(key) : nil
        end

        def []=(key, value)
          assign_attributes(key => value)
        end

        def ==(other)
          other.class == self.class && other.attributes == attributes
        end
        alias eql? ==

        def empty?
          @attributes.keys.empty?
        end

        def hash
          [self.class, attributes].hash
        end

        def to_h
          attributes.symbolize_keys
        end

        def inspect
          entries = attributes.map { |key, value| "#{key}: #{value.inspect}" }
          "#<#{self.class.name} #{entries.join(', ')}>"
        end

        def type_for_attribute(name, &block)
          self.class.type_for_attribute(name, &block)
        end

        def read_attribute_before_type_cast(name)
          @attributes[name.to_s].value_before_type_cast
        end

        def read_attribute_for_database(name)
          @attributes[name.to_s].value_for_database
        end
      end
    end
  end
end
