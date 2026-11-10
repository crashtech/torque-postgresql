# frozen_string_literal: true

require_relative 'base'

module Torque
  module PostgreSQL
    module Attributes
      class Composite < Base
        class << self
          attr_writer :type_name

          # Find or create the class that will handle the composite type. It
          # first checks the irregular types mapping, then the namespace
          def lookup(name)
            name = name.to_s.underscore
            mapping = PostgreSQL.config.composite.irregular_types
            return resolve(mapping[name].constantize, name) if mapping.key?(name)

            const     = name.camelize
            namespace = PostgreSQL.config.composite.namespace

            return resolve(namespace.const_get(const), name) if namespace.const_defined?(const)
            resolve(namespace.const_set(const, Class.new(Composite)), name)
          end

          def inherited(subclass)
            super
            subclass.instance_variable_set(:@load_columns_monitor, ::Monitor.new)
          end

          # The name of the composite type on the database
          def type_name
            @type_name ||= name.demodulize.underscore
          end

          # The ordered list of columns of the composite type, as a hash of
          # name and type, loaded in a lazy way
          def columns
            load_columns
            @columns
          end

          # Load the columns from the database and define any attribute that
          # was not manually declared
          def load_columns
            return if self == Composite || defined?(@columns)

            @load_columns_monitor.synchronize do
              next if defined?(@columns)

              columns = ActiveRecord::Base.with_connection { |c| c.composite_column_types(type_name) }
              columns.each do |attr_name, attr_type|
                attribute(attr_name, attr_type) unless attribute_names.include?(attr_name)
              end

              @columns = columns
            end
          end

          # Drop the loaded columns, so that they are collected again on the
          # next use, which happens after the type is changed
          def reset_columns!
            @load_columns_monitor.synchronize do
              remove_instance_variable(:@columns) if defined?(@columns)
            end
          end

          def new(*args, **xargs, &block)
            load_columns
            super
          end

          # Columns have to be in place before any of them can be decorated
          def encrypts(*names, **options)
            load_columns
            super
          end

          def enum(*args, **xargs)
            load_columns
            super
          end

          private

            # Make sure that the class knows the name of the type it handles,
            # since it can be resolved from an irregular mapping
            def resolve(klass, name)
              klass.type_name = name
              klass
            end
        end
      end
    end

    Composite = Attributes::Composite
  end
end
