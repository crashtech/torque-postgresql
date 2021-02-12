# frozen_string_literal: true

require_relative 'adapter/database_statements'
require_relative 'adapter/oid'
require_relative 'adapter/quoting'
require_relative 'adapter/schema_creation'
require_relative 'adapter/schema_definitions'
require_relative 'adapter/schema_dumper'
require_relative 'adapter/schema_statements'

module Torque
  module PostgreSQL
    module Adapter
      include Quoting
      include DatabaseStatements
      include SchemaStatements

      INJECT_WHERE_REGEX = /(DO UPDATE SET.*excluded\.[^ ]+) RETURNING/.freeze

      # Get the current PostgreSQL version as a Gem Version.
      def version
        @version ||= Gem::Version.new(
          select_value('SELECT version()').match(/#{Adapter::ADAPTER_NAME} ([\d\.]+)/)[1]
        )
      end

      # Add `inherits` to the list of extracted table options
      def extract_table_options!(options)
        super.merge(options.extract!(:inherits))
      end

      # Allow filtered bulk insert by adding the where clause. This method is only used by
      # +InsertAll+, so it somewhat safe to override it
      def build_insert_sql(insert)
        super.tap do |sql|
          if insert.update_duplicates? && insert.where_condition?
            if insert.returning
              sql.gsub!(INJECT_WHERE_REGEX, "\\1 WHERE #{insert.where} RETURNING")
            else
              sql << " WHERE #{insert.where}"
            end
          end
        end
      end
    end

    ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend Adapter
  end
end
