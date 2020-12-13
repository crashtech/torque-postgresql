# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module SchemaDumper
        def dump(stream) # :nodoc:
          @connection.dump_mode!
          super

          @connection.dump_mode!
          stream
        end

        def extensions(stream) # :nodoc:
          super
          user_defined_types(stream)
        end

        # Translate +:enum_set+ into +:enum+
        def schema_type(column)
          column.type == :enum_set ? :enum : super
        end

        # Adds +:subtype+ option to the default set
        def prepare_column_options(column)
          spec = super

          if subtype = schema_subtype(column)
            spec[:subtype] = subtype
          end

          spec
        end

        private

          def schema_subtype(column)
            column.sql_type.to_sym.inspect if column.type == :enum || column.type == :enum_set
          end

          def tables(stream) # :nodoc:
            inherited_tables = @connection.inherited_tables
            sorted_tables = @connection.tables.sort - @connection.views

            stream.puts "  # These are the common tables managed"
            (sorted_tables - inherited_tables.keys).each do |table_name|
              table(table_name, stream) unless ignored?(table_name)
            end

            if inherited_tables.present?
              stream.puts "  # These are tables that has inheritance"
              inherited_tables.each do |table_name, inherits|
                next if ignored?(table_name)

                sub_stream = StringIO.new
                table(table_name, sub_stream)

                # Add the inherits setting
                sub_stream.rewind
                inherits.map!(&:to_sym)
                inherits = inherits.first if inherits.size === 1
                inherits = ", inherits: #{inherits.inspect} do |t|"
                table_dump = sub_stream.read.gsub(/ do \|t\|$/, inherits)

                # Ensure bodyless definitions
                table_dump.gsub!(/do \|t\|\n  end/, '')
                stream.print table_dump
              end
            end

            # Dump foreign keys at the end to make sure all dependent tables exist.
            if @connection.supports_foreign_keys?
              sorted_tables.each do |tbl|
                foreign_keys(tbl, stream) unless ignored?(tbl)
              end
            end

            # Scenic integration
            views(stream) if defined?(::Scenic)
          end

          # Dump user defined types like enum
          def user_defined_types(stream)
            types = @connection.user_defined_types('e')
            return unless types.any?

            stream.puts "  # These are user-defined types used on this database"
            types.sort_by(&:first).each { |(name, type)| send(type.to_sym, name, stream) }
            stream.puts
          rescue => e
            stream.puts "# Could not dump user-defined types because of following #{e.class}"
            stream.puts "#   #{e.message}"
            stream.puts
          end

          # Dump enum custom type
          def enum(name, stream)
            values = @connection.enum_values(name).map { |v| "\"#{v}\"" }
            stream.puts "  create_enum \"#{name}\", [#{values.join(', ')}], force: :cascade"
          end
      end

      ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper.prepend SchemaDumper
    end
  end
end
