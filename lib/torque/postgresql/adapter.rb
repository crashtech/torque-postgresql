
require_relative 'adapter/composite_column'
require_relative 'adapter/database_statements'
require_relative 'adapter/oid'
require_relative 'adapter/quoting'
require_relative 'adapter/schema_definitions'
require_relative 'adapter/schema_dumper'
require_relative 'adapter/schema_statements'

module Torque
  module PostgreSQL
    module Adapter

      include Quoting
      include ColumnDumper
      include DatabaseStatements

      # Get the current PostgreSQL version as a Gem Version.
      def version
        @version ||= Gem::Version.new(
          select_value('SELECT version()')
            .match(/#{Adapter::ADAPTER_NAME} ([\d\.]+)/)[1])
      end

      # Change some of the types being mapped
      def initialize_type_map(m)
        super
        m.register_type 'interval', OID::Interval.new
      end

      # Configure the interval format
      def configure_connection
        super
        execute("SET SESSION IntervalStyle TO 'iso_8601'", 'SCHEMA')
      end

    end

    ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend Adapter
  end
end
