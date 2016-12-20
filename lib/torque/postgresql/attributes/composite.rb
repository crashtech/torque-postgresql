module Torque
  module PostgreSQL
    module Attributes
      module Composite

        # Where the composite types classes will be defined
        SCOPE = ::Object

        class << self

          # Find or create the class that will handle the field
          def lookup(name)
            const = name.camelize
            return SCOPE.const_get(const) if SCOPE.const_defined?(const)
            SCOPE.const_set(const, Base.define_from_type(name))
          end

        end

        class Decorator < ActiveModel::Type::Value
          include ActiveModel::Type::Helpers::Mutable

          attr_reader :subtype, :type, :parent, :attribute

          # Decorate the value for a given composition.
          def initialize(type, subtype)
            @type      = type
            @subtype   = subtype
          end

          # Bind the currect instance to an model instance and an attribute
          def bind(parent, attribute)
            @parent    = parent
            @attribute = attribute
          end

          # Type casts a value from user input (e.g. from a setter).
          def cast(value)
            return value.bind(parent, attribute) if value.is_a?(Base)

            list = subtype.cast(value)
            to_model.tap do |entry|
              list = entry.class.column_names.zip(list).to_h if list.is_a?(Array)
              entry.attributes = list unless list.blank?
            end
          end

          # Converts a value from database input to the appropriate ruby type.
          def deserialize(value)
            list = subtype.deserialize(value)
            to_model.tap do |entry|
              entry.attributes = entry.class.column_names.zip(list).to_h unless list.blank?
            end
          end

          # Casts a value from the ruby type to a type that the database knows
          # how to understand.
          def serialize(value)
            subtype.serialize(value.attributes.values)
          end

          # Get the prepared model to use as a value.
          def to_model
            Composite.lookup(type).new.bind(parent, attribute)
          end

        end

        class Base < ActiveRecord::Base

          # Methods to be better understood
          # new_record? destroyed? persisted?
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

        end

      end
    end
  end
end
