# frozen_string_literal: true

module Torque
  module PostgreSQL
    class TableName < Delegator
      def initialize(klass, table_name)
        @klass = klass
        @table_name = table_name
      end

      def schema
        return @schema if defined?(@schema)

        @schema = ([@klass] + @klass.module_parents[0..-2]).find do |klass|
          next unless klass.respond_to?(:schema)
          break klass.schema
        end
      end

      def to_s
        schema.nil? ? @table_name : "#{schema}.#{@table_name}"
      end

      alias __getobj__ to_s

      def ==(other)
        other.to_s =~ /("?#{schema | search_path_schemes.join('|')}"?\.)?"?#{@table_name}"?/
      end

      def __setobj__(value)
        @table_name = value
      end

      private

        def search_path_schemes
          klass.connection.schemas_search_path_sanitized
        end
    end
  end
end
