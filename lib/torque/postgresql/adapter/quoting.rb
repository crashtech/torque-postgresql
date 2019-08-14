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
          if value.is_a?(Array)
            quote(value) + '::' + column.sql_type
          else
            super
          end
        end

        private

          def _quote(value)
            case value
            when Array
              values = value.map(&method(:quote))
              "ARRAY[#{values.join(',')}]"
            else
              super
            end
          end
      end
    end
  end
end
