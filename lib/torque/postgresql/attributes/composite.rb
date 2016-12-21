module Torque
  module PostgreSQL
    module Attributes
      module Composite

        class << self

          # Find or create the class that will handle the field
          def lookup(name)
            const     = name.camelize
            namespace = Torque::PostgreSQL.config.composite.namespace

            return namespace.const_get(const) if namespace.const_defined?(const)
            namespace.const_set(const, Base.define_from_type(name))
          end

        end

        # class Decorator < ActiveModel::Type::Value
        #   include ActiveModel::Type::Helpers::Mutable
        #   include Attributes::Bindable

        #   attr_reader :subtype, :type

        #   # Decorate the value for a given composition.
        #   def initialize(type, subtype)
        #     @type    = type
        #     @subtype = subtype
        #   end

        #   # Type casts a value from user input (e.g. from a setter).
        #   def cast(value)
        #     return value if value.is_a?(Base)

        #     list = subtype.cast(value)
        #     to_model.tap do |entry|
        #       list = entry.class.column_names.zip(list).to_h if list.is_a?(Array)
        #       entry.attributes = list unless list.blank?
        #     end
        #   end

        #   # Converts a value from database input to the appropriate ruby type.
        #   def deserialize(value)
        #     list = subtype.deserialize(value)
        #     to_model.tap do |entry|
        #       entry.attributes = entry.class.column_names.zip(list).to_h unless list.blank?
        #     end
        #   end

        #   # Casts a value from the ruby type to a type that the database knows
        #   # how to understand.
        #   def serialize(value)
        #     subtype.serialize(value.attributes.values)
        #   end

        #   # Get the prepared model to use as a value.
        #   def to_model
        #     Composite.lookup(type).new
        #   end

        # end

        class Base < DelegateClass(ActiveRecord::Base)
          include Attributes

          # Methods to be better understood
          # new_record? destroyed? persisted? table_exists?
          # ActiveRecord::Persistence
          delegate :save, :save!, :delete, :destroy, :destroy!, :reload, :touch,
                   to: :@bind_parent

          class << self

            attr_reader :type

            # Generate a model class that is defined as a shared user-defined
            # type.
            def define_from_type(name)
              klass = Class.new(Base)
              klass.instance_variable_set(:@type, name)
              klass.send(:load_schema)
              klass
            end

            # The process of loading the schema is very different from a normal
            # table table reading and defining
            def load_schema!
              columns = connection.schema_cache.columns_hash(type, true)
              @columns_hash = columns.except(*ignored_columns)
              @columns_hash.each do |name, column|
                warn_if_deprecated_type(column)
                define_attribute(
                  name,
                  connection.lookup_cast_type_from_column(column),
                  default: column.default,
                  user_provided_default: false
                )
              end
            end

            # Prints as composite model
            def inspect
              attr_list = attribute_types.map { |name, type| "#{name}: #{type.type}" } * ', '
              "#{name} Type (#{attr_list})"
            end

          end

          # Bind the composition model to a parent model
          def bind(parent, attribute)
            @bind_parent = parent
            @bind_attribute = attribute
            self
          end

          # Add the Type string to the inspection
          def inspect
            super.insert(2 + self.class.name.length, ' Type')
          end

        end

        # Create the methods related to the attribute to handle the composite type
        TypeMap.register_type Adapter::OID::Composite do |attribute|
          return unless Torque::PostgreSQL.config.composite.initializer
          puts attribute

          # return if attributes_with_bindable_types.key? attribute

          # decorate_attribute_type(attribute, :composite) do |subtype|
          #   decorator = Composite::Decorator.new(type.name, subtype)
          #   attributes_with_bindable_types[attribute] = decorator
          # end
        end

      end
    end
  end
end
