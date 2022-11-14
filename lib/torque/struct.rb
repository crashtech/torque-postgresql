
require "active_support/concern"
require "torque/postgresql/adapter"

module Torque
  class BaseStruct
    def to_s
      # Avoid printing excessive volumes
      "#<#{self.class.name}>"
    end

    def _run_find_callbacks
    end
    def _run_initialize_callbacks
    end

    class << self
      def connection
        # Lets you overwrite `connection` per-class
        ActiveRecord::Base.connection
      end
      class_attribute :primary_key
      self.primary_key = "id"

      def base_class?
        self == BaseStruct || self == Struct
      end

      def base_class
        BaseStruct
      end

      def table_name
        nil
      end

      def abstract_class?
        base_class?
      end
    end
  end
  class Struct < BaseStruct
    include ActiveRecord::Core
    include ActiveRecord::Persistence
    include ActiveRecord::ModelSchema
    include ActiveRecord::Attributes
    include ActiveRecord::AttributeMethods
    include ActiveRecord::Serialization
    include ActiveRecord::AttributeAssignment
    self.pluralize_table_names = false
    def initialize(attributes = nil)
      @attributes = self.class.attributes_builder.build_from_database
      assign_attributes(attributes) if attributes
      self.class.define_attribute_methods
      yield self if block_given?
    end

    class << self

      # ActiveRecord modules call `superclass.foo`, so we need an extra layer of inheritance
      def database_type
        ::Torque::PostgreSQL::Adapter::OID::Struct.for_type(table_name, klass: self)
      end

      def database_array_type
        ::Torque::PostgreSQL::Adapter::OID::Struct.for_type(table_name + "[]", klass: self)
      end

      def table_exists?
        ::Torque::PostgreSQL::Adapter::OID::Struct.for_type(table_name).present?
      end

      def type_name
        table_name
      end
      def type_name=(value)
        @type_name = value
      end
      def table_name
        return @type_name if @type_name
        if self === Struct
          nil
        else
          self.name.underscore
        end
      end
    end
  end

  class ActiveRecord::Base
    class << self
      def database_type
        ::Torque::PostgreSQL::Adapter::OID::Struct.for_type(table_name, klass: self)
      end

      def database_array_type
        ::Torque::PostgreSQL::Adapter::OID::Struct.for_type(table_name + "[]", klass: self)
      end
    end
  end
end
