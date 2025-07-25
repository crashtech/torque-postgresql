# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module Quoting
        QUOTED_TYPE_NAMES = Concurrent::Map.new

        Name = ActiveRecord::ConnectionAdapters::PostgreSQL::Name
        Column = ActiveRecord::ConnectionAdapters::PostgreSQL::Column
        ColumnDefinition = ActiveRecord::ConnectionAdapters::ColumnDefinition
        Utils = ActiveRecord::ConnectionAdapters::PostgreSQL::Utils

        # Quotes type names for use in SQL queries.
        def quote_type_name(name, *args)
          QUOTED_TYPE_NAMES[args] ||= begin
            name = name.to_s
            args << 'public' if args.empty? && !name.include?('.')
            quote_identifier_name(name, *args)
          end
        end

        # Make sure to support all sorts of different compositions of names
        def quote_identifier_name(name, schema = nil)
          name = Utils.extract_schema_qualified_name(name.to_s) unless name.is_a?(Name)
          name.instance_variable_set(:@schema, Utils.unquote_identifier(schema.to_s)) if schema
          name.quoted.freeze
        end

        def quote_default_expression(value, column)
          return super unless value.class <= Array || value.class <= Set

          type =
            if column.is_a?(ColumnDefinition) && column.options.try(:[], :array)
              # This is the general way
              lookup_cast_type(column.sql_type)
            elsif column.is_a?(Column) && column.array?
              # When using +change_column_default+
              lookup_cast_type_from_column(column)
            end

          type.nil? ? super : quote(type.serialize(value.to_a))
        end
      end
    end
  end
end
