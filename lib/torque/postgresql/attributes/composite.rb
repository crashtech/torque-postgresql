module Torque
  module PostgreSQL
    module Attributes
      module Composite
        class CompositeError < StandardError; end

        class << self

          # Get the constant name given a type name
          def const_name(name)
            lookup(name).name
          end

          # Find or create the class that will handle the field
          def lookup(name)
            const     = name.camelize
            namespace = Torque::PostgreSQL.config.composite.namespace

            return namespace.const_get(const) if namespace.const_defined?(const)
            namespace.const_set(const, Base.define_from_type(name))
          end

        end

        class Base < ActiveRecord::Base
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

            # Get the direct OID composite type
            def oid_type
              connection.type_map.lookup(type)
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

            # Based on a type name, instantiate a new relation class
            def modelize(parent, attribute, values = nil)
              instantiate(cast_value(values)).bind(parent, attribute)
            end

            # Cast a value to a model attributes
            def cast_value(value)
              case value
              when Base
                value.attributes
              when String
                cast_value(oid_type.deserialize(value))
              when Hash
                value.with_indifferent_access.slice(*column_names)
              when Array
                column_names.zip(value).to_h
              else
                column_names.zip([]).to_h
              end
            end

            # Composite types does not have tables
            def table_exists?
              false
            end

            # Prints as composite model
            def inspect
              if self == Base
                shortcut = Torque::PostgreSQL.config.composite.shortcut
                shortcut.present? ? "ActiveRecord::#{shortcut}" : name
              else
                attr_list = attribute_types.map { |name, type| "#{name}: #{type.type}" }
                "#{name} Type (#{attr_list.join(', ')})"
              end
            end

            private

              # Replace the method that gets the arel table to throw an error
              def arel_table
                raise CompositeError, 'Composite models are not direct related to tables'
              end

              # Replace the relation method so it can't be created from composite types
              def relation
                raise CompositeError, 'Queries cannot be created from composite models'
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

        # Defines a shortcut access to composite base model class
        if Torque::PostgreSQL.config.composite.shortcut.present?
          ActiveRecord.const_set(Torque::PostgreSQL.config.composite.shortcut, Base)
        end

        # Create the methods related to the attribute to handle the composite type
        TypeMap.register_type Adapter::OID::Composite do |subtype, attribute, initial = false|
          return if initial && !Torque::PostgreSQL.config.composite.initializer
          relation = Composite.lookup(subtype.name)

          # Create all methods needed
          Builder::Composite.new(self, attribute, relation).build

          # Build the options for aggregate reflection
          options = {class_name: relation.name, allow_nil: true, composite: true}

          # Register the aggregate reflection
          reflection = ActiveRecord::Reflection.create(:composed_of, attribute, nil, options, self)
          ActiveRecord::Reflection.add_aggregate_reflection self, attribute, reflection
        end

      end
    end
  end
end
