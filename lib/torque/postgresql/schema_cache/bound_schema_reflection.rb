# frozen_string_literal: true

module Torque
  module PostgreSQL
    module BoundSchemaReflection
      def add_model_name(connection, table_name, model)
        @schema_reflection.add_model_name(connection, table_name, model)
      end

      def dependencies(table_name)
        @schema_reflection.dependencies(@connection, table_name)
      end

      def associations(table_name)
        @schema_reflection.associations(@connection, table_name)
      end

      def lookup_model(table_name, scoped_class = '')
        @schema_reflection.lookup_model(@connection, table_name, scoped_class)
      end
    end

    ActiveRecord::ConnectionAdapters::BoundSchemaReflection.prepend BoundSchemaReflection
  end
end
