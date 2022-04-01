# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module Quoting

        Name = ActiveRecord::ConnectionAdapters::PostgreSQL::Name
        Column = ActiveRecord::ConnectionAdapters::PostgreSQL::Column
        ColumnDefinition = ActiveRecord::ConnectionAdapters::ColumnDefinition

        # Quotes type names for use in SQL queries.
        def quote_type_name(string, schema = nil)
          name_schema, table = string.to_s.scan(/[^".\s]+|"[^"]*"/)
          if table.nil?
            table = name_schema
            name_schema = nil
          end

          schema = schema || name_schema || 'public'
          Name.new(schema, table).quoted
        end
      end
    end
  end
end
