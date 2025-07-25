module Torque
  module PostgreSQL
    module Adapter
      module SchemaCreation

        # Inherits are now setup via table options, but keep the implementation
        # supported by this gem
        def add_table_options!(create_sql, o)
          if o.inherits.present?
            # Make sure we always have parenthesis
            create_sql << '()' unless create_sql[-1] == ')'

            tables = o.inherits.map(&method(:quote_table_name))
            create_sql << " INHERITS ( #{tables.join(' , ')} )"
          end

          super(create_sql, o)
        end
      end

      ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaCreation.prepend SchemaCreation
    end
  end
end
