module Torque
  module PostgreSQL
    module SchemaDumper

      def extensions(stream)
        super
        user_defined_types(stream)
      end

      private

        def user_defined_types(stream)
          types = @connection.user_defined_types
          return unless types.any?

          stream.puts "  # These are user-defined types used on this database"
          types.each do |name, type|
            raise StandardError, "User-defined type '#{name}' cannot be dumped!" if type.blank?
            send(type.to_sym, name, stream)
          end
          stream.puts
        rescue => e
          stream.puts "# Could not dump user-defined types because of following #{e.class}"
          stream.puts "#   #{e.message}"
          stream.puts
        end

        def enum(name, stream)
          values = @connection.enum_values(name).map { |v| "\"#{v}\"" }
          stream.puts "  create_enum \"#{name}\", [#{values.join(', ')}], force: :cascade"
        end

        def composite(name, stream)
          stream.puts

          columns = @connection.composite_columns(name)
          type = StringIO.new

          type.puts "  create_composite_type #{name.inspect}, force: :cascade do |t|"

          # then dump all non-primary key columns
          column_specs = columns.map do |column|
            raise StandardError, "Unknown type '#{column.sql_type}' for column '#{column.name}'" unless @connection.valid_type?(column.type)
            @connection.column_spec(column)
          end.compact

          # find all migration keys used in this table
          keys = @connection.migration_keys

          # figure out the lengths for each column based on above keys
          lengths = keys.map { |key|
            column_specs.map { |spec|
              spec[key] ? spec[key].length + 2 : 0
            }.max
          }

          # the string we're going to sprintf our values against, with standardized column widths
          format_string = lengths.map{ |len| "%-#{len}s" }

          # find the max length for the 'type' column, which is special
          type_length = column_specs.map{ |column| column[:type].length }.max

          # add column type definition to our format string
          format_string.unshift "    t.%-#{type_length}s "

          format_string *= ''

          column_specs.each do |colspec|
            values = keys.zip(lengths).map{ |key, len| colspec.key?(key) ? colspec[key] + ", " : " " * len }
            values.unshift colspec[:type]
            type.print((format_string % values).gsub(/,\s*$/, ''))
            type.puts
          end

          type.puts "  end"
          type.rewind

          stream.print type.read
        rescue => e
          stream.puts "# Could not dump user-defined composite type #{name.inspect} because of following #{e.class}"
          stream.puts "#   #{e.message}"
          stream.puts
        end

    end

    ActiveRecord::SchemaDumper.prepend SchemaDumper
  end
end
