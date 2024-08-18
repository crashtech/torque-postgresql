# frozen_string_literal: true

module Torque
  module PostgreSQL
    module SchemaReflection
      def add_model_name(source, table_name, model)
        cache(source).add_model_name(source, table_name, model)
      end

      def dependencies(source, table_name)
        cache(source).dependencies(source, table_name)
      end

      def associations(source, table_name)
        cache(source).associations(source, table_name)
      end

      def lookup_model(source, table_name, scoped_class)
        cache(source).lookup_model(table_name, scoped_class)
      end
    end

    ActiveRecord::ConnectionAdapters::SchemaReflection.prepend SchemaReflection
  end
end
