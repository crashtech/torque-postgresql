# frozen_string_literal: true

module Torque
  module PostgreSQL
    module BoundSchemaReflection
      def add_model_name(table_name, model)
        source = defined?(@pool) ? @pool : @connection
        @schema_reflection.add_model_name(source, table_name, model)
      end

      def dependencies(table_name)
        source = defined?(@pool) ? @pool : @connection
        @schema_reflection.dependencies(source, table_name)
      end

      def associations(table_name)
        source = defined?(@pool) ? @pool : @connection
        @schema_reflection.associations(source, table_name)
      end

      def lookup_model(table_name, scoped_class = '')
        source = defined?(@pool) ? @pool : @connection
        @schema_reflection.lookup_model(source, table_name, scoped_class)
      end
    end

    ActiveRecord::ConnectionAdapters::BoundSchemaReflection.prepend BoundSchemaReflection
  end
end
