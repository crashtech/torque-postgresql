module Torque
  module Postgresql
    module Migration

      Dumper    = ActiveRecord::SchemaDumper

      Connector = ActiveRecord::ConnectionAdapters::PostgreSQL
      Adapter   = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter

      Migration = ActiveRecord::Migration
      Reversion = Migration::CommandRecorder

      Utils     = Connector::Utils

      module Helper
        # Get the current PostgreSQL version.
        def version
          @version ||= Gem::Version.new(
            select_value('SELECT version()')
              .match(/#{Adapter::ADAPTER_NAME} ([\d\.]+)/)[1])
        end

        # Adds +:subtype+ as a valid migration key
        def migration_keys
          super + [:subtype]
        end

        def prepare_column_options(column)
          spec = super

          if subtype = schema_subtype(column)
            spec[:subtype] = subtype
          end

          spec
        end

        def schema_subtype(column)
          column.sql_type.to_sym.inspect if [:enum, :composite].include? column.type
        end

      end

      module Quoting
        # Quotes type names for use in SQL queries.
        def quote_type_name(name)
          PGconn.quote_ident(name.to_s)
        end

        private

          def _type_cast(value)
            # TODO: Fix quotes issue
            return super unless value.is_a? CompositeOID::Data
            "(#{value.map(&method(:type_cast)).join(value.delim)})"
          end

      end

      Adapter.send :include, Helper
      Adapter.send :include, Quoting

    end
  end
end

require 'torque/postgresql/migration/types'
require 'torque/postgresql/migration/enum'
require 'torque/postgresql/migration/composite'
