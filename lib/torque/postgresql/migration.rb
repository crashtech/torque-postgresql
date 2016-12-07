module Torque
  module Postgresql
    module Migration

      Connector = ActiveRecord::ConnectionAdapters::PostgreSQL
      Adapter   = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter

      Utils     = Connector::Utils

      module Helper
        # Get the current PostgreSQL version.
        def version
          @version ||= Gem::Version.new(
            select_value('SELECT version()')
              .match(/#{Adapter::ADAPTER_NAME} ([\d\.]+)/)[1])
        end
      end

      module Quoting
        # Quotes type names for use in SQL queries.
        def quote_type_name(name)
          PGconn.quote_ident(name.to_s)
        end
      end

      Adapter.send :include, Helper
      Adapter.send :include, Quoting

    end
  end
end

require 'torque/postgresql/migration/enum'
