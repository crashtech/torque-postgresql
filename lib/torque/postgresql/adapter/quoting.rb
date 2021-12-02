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

        def quote_default_expression(value, column)
          return super unless value.class <= Array &&
            ((column.is_a?(ColumnDefinition) && column.dig(:options, :array)) ||
            (column.is_a?(Column) && column.array?))

          type = column.is_a?(Column) ? column.sql_type_metadata.sql_type : column.sql_type
          quote(value) + '::' + type
        end

        private

          def _quote(value)
            return super unless value.is_a?(Array)

            values = value.map(&method(:quote))
            "ARRAY[#{values.join(','.freeze)}]"
          end

          def _type_cast(value)
            return super unless value.is_a?(Array)
            value.map(&method(:quote)).join(','.freeze)
          end
      end
    end
  end
end
