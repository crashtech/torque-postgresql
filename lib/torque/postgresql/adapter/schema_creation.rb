module Torque
  module PostgreSQL
    module Adapter
      module SchemaCreation

        delegate :quote_type_name, to: :@conn

        private

          def visit_CompositeTypeDefinition(o)
            create_sql = "CREATE TYPE #{quote_type_name(o.name)} "
            statements = o.columns.map { |c| accept c }

            create_sql << "AS (#{statements.join(', ')})" if statements.present?
            create_sql << "AS (#{@conn.to_sql(o.as)})" if o.as
            create_sql
          end

      end

      ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaCreation.include SchemaCreation
    end
  end
end
