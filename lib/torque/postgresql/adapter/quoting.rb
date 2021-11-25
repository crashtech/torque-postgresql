# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module Quoting

        Name = ActiveRecord::ConnectionAdapters::PostgreSQL::Name

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
          if column.options.try(:[], :array) && value.class <= Array
            quote(value) + '::' + column.sql_type
          else
            super
          end
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
