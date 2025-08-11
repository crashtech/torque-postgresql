# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module SchemaDumper
        SEARCH_VECTOR_SCANNER = /
          to_tsvector\(
            ('[^']+'|[a-z][a-z0-9_]*)[^,]*,[^\(]*
            \(?coalesce\(([a-z][a-z0-9_]*)[^\)]*\)\)?
          (?:::[^\)]*\))?
          (?:\s*,\s*'([A-D])')?
        /ix

        def initialize(*)
          super

          if with_versioned_commands?
            @versioned_commands = VersionedCommands::SchemaTable.new(@connection.pool)
            @ignore_tables << @versioned_commands.table_name
          end
        end

        def dump(stream) # :nodoc:
          @connection.dump_mode!
          super

          @connection.dump_mode!
          stream
        end

        private

          def types(stream) # :nodoc:
            super

            versioned_commands(stream, :type)
            versioned_commands(stream, :function)
          end

          def tables(stream) # :nodoc:
            around_tables(stream) { dump_tables(stream) }
          end

          def around_tables(stream)
            functions(stream) if fx_functions_position == :beginning

            yield
            versioned_commands(stream, :view, true)

            functions(stream) if fx_functions_position == :end
            triggers(stream) if defined?(::Fx::SchemaDumper::Trigger)
          end

          def dump_tables(stream)
            inherited_tables = @connection.inherited_tables
            sorted_tables = (@connection.tables - @connection.views).filter_map do |table_name|
              name_parts = table_name.split(/(?:public)?\./).reverse.compact_blank
              next if ignored?(table_name) || ignored?(name_parts.join('.'))

              [table_name, name_parts]
            end.sort_by(&:last).to_h

            postponed = []

            stream.puts "  # These are the common tables"
            sorted_tables.each do |table, (table_name, _)|
              next postponed << table if inherited_tables.key?(table_name)

              table(table, stream)
              stream.puts # Ideally we would not do this in the last one
            end

            if postponed.present?
              stream.puts "  # These are tables that have inheritance"
              postponed.each do |table|
                sub_stream = StringIO.new
                table(table, sub_stream)
                stream.puts sub_stream.string.sub(/do \|t\|\n  end/, '')
                stream.puts
              end
            end

            # Fixes double new lines to single new lines
            stream.pos -= 1

            # dump foreign keys at the end to make sure all dependent tables exist.
            if @connection.supports_foreign_keys?
              foreign_keys_stream = StringIO.new
              sorted_tables.each do |(tbl, *)|
                foreign_keys(tbl, foreign_keys_stream)
              end

              foreign_keys_string = foreign_keys_stream.string
              stream.puts if foreign_keys_string.length > 0
              stream.print foreign_keys_string
            end
          end

          # Make sure to remove the schema from the table name
          def remove_prefix_and_suffix(table)
            super(table.sub(/\A[a-z0-9_]*\./, ''))
          end

          # Dump user defined schemas
          def schemas(stream)
            return super if !PostgreSQL.config.schemas.enabled
            return if (list = (@connection.user_defined_schemas - ['public'])).empty?

            stream.puts "  # Custom schemas defined in this database."
            list.each { |name| stream.puts "  create_schema \"#{name}\", force: :cascade" }
            stream.puts
          end

          # Adjust the schema type for search vector
          def schema_type_with_virtual(column)
            column.virtual? && column.type == :tsvector ? :search_vector : super
          end

          # Adjust the schema type for search language
          def schema_type(column)
            column.sql_type == 'regconfig' ? :search_language : super
          end

          # Adjust table options to make the dump more readable
          def prepare_column_options(column)
            options = super
            parse_search_vector_options(column, options) if column.type == :tsvector
            options
          end

          # Parse the search vector operation into a readable format
          def parse_search_vector_options(column, options)
            settings = options[:as].scan(SEARCH_VECTOR_SCANNER)
            return if settings.empty?

            languages = settings.map(&:shift).uniq
            return if languages.many?

            language = languages.first
            language = language[0] == "'" ? language[1..-2] : language.to_sym
            columns = parse_search_vector_columns(settings)

            options.except!(:as, :type)
            options.merge!(language: language.inspect, columns: columns)
          end

          # Simplify the whole columns configuration to make it more manageable
          def parse_search_vector_columns(settings)
            return ":#{settings.first.first}" if settings.one?

            settings = settings.sort_by(&:last)
            weights = %w[A B C D]

            columns = settings.each.with_index.reduce([]) do |acc, (setting, index)|
              column, weight = setting
              break if (weights[index] || 'D') != weight

              acc << column
              acc
            end

            return columns.map(&:to_sym).inspect if columns
            settings.to_h.transform_values(&:inspect)
          end

          # Simply add all versioned commands to the stream
          def versioned_commands(stream, type, add_newline = false)
            return unless with_versioned_commands?

            list = @versioned_commands.versions_of(type.to_s)
            return if list.empty?

            existing = list_existing_versioned_commands(type)

            stream.puts if add_newline
            stream.puts "  # These are #{type.to_s.pluralize} managed by versioned commands"
            list.each do |(name, version)|
              next if existing.exclude?(name)

              stream.puts "  create_#{type} \"#{name}\", version: #{version}"
            end
            stream.puts unless add_newline
          end

          def list_existing_versioned_commands(type)
            @connection.list_versioned_commands(type).each_with_object(Set.new) do |entry, set|
              set << (entry.first == 'public' ? entry.last : entry.join('_'))
            end
          end

          def with_versioned_commands?
            PostgreSQL.config.versioned_commands.enabled
          end

          def fx_functions_position
            return unless defined?(::Fx::SchemaDumper::Function)
            Fx.configuration.dump_functions_at_beginning_of_schema ? :beginning : :end
          end
      end

      ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper.prepend SchemaDumper
    end
  end
end
