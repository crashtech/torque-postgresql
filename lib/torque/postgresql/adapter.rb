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

      # Get the current PostgreSQL version as a Gem Version.
      def version
        @version ||= Gem::Version.new(
          select_value('SELECT version()').match(/#{Adapter::ADAPTER_NAME} ([\d\.]+)/)[1]
        )
      end
    end

    ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend Adapter
  end
end
