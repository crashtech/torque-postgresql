# frozen_string_literal: true

module Torque
  module PostgreSQL
    module SchemaReflection
      def add_model_name(connection, table_name, model)
        cache(connection).add_model_name(table_name, model)
      end

      def dependencies(connection, table_name)
        cache(connection).dependencies(connection, table_name)
      end

      def associations(connection, table_name)
        cache(connection).associations(connection, table_name)
      end

      def lookup_model(connection, table_name, scoped_class)
        cache(connection).lookup_model(table_name, scoped_class)
      end
    end

    ActiveRecord::ConnectionAdapters::SchemaReflection.prepend SchemaReflection
  end
end
