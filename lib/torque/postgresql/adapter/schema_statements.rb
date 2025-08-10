# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module SchemaStatements
        # Drops a type
        def drop_type(name, options = {})
          force = options.fetch(:force, '').upcase
          check = 'IF EXISTS' if options.fetch(:check, true)
          name = sanitize_name_with_schema(name, options)

          internal_exec_query(<<-SQL.squish).tap { reload_type_map }
            DROP TYPE #{check}
            #{quote_type_name(name)} #{force}
          SQL
        end

        # Renames a type
        def rename_type(type_name, new_name, options = {})
          type_name = sanitize_name_with_schema(type_name, options)
          internal_exec_query(<<-SQL.squish).tap { reload_type_map }
            ALTER TYPE #{quote_type_name(type_name)}
            RENAME TO #{Quoting::Name.new(nil, new_name.to_s).quoted}
          SQL
        end

        # Creates a column that stores the underlying language of the record so
        # that a search vector can be created dynamically based on it. It uses
        # a `regconfig` type, so string conversions are mandatory
        def add_search_language(table, name, options = {})
          add_column(table, name, :regconfig, options)
        end

        # Creates a column and setup a search vector as a virtual column. The
        # options are dev-friendly and controls how the vector function will be
        # defined
        #
        # === Options
        # [:columns]
        #   The list of columns that will be used to create the search vector.
        #   It can be a single column, an array of columns, or a hash as a
        #   combination of column name and weight (A, B, C, or D).
        # [:language]
        #   Specify the language config to be used for the search vector. If a
        #   string is provided, then the value will be statically embedded. If a
        #   symbol is provided, then it will reference another column.
        # [:stored]
        #   Specify if the value should be stored in the database. As of now,
        #   PostgreSQL only supports `true`, which will create a stored column.
        def add_search_vector(table, name, columns, options = {})
          options = Builder.search_vector_options(columns: columns, **options)
          add_column(table, name, options.delete(:type), options)
        end

        # Changes the enumerator by adding new values
        #
        # Example:
        #   add_enum_values 'status', ['baz']
        #   add_enum_values 'status', ['baz'], before: 'bar'
        #   add_enum_values 'status', ['baz'], after: 'foo'
        #   add_enum_values 'status', ['baz'], prepend: true
        def add_enum_values(name, values, options = {})
          name   = sanitize_name_with_schema(name, options)
          before = options.fetch(:before, false)
          after  = options.fetch(:after,  false)

          before = enum_values(name).first if options.key? :prepend
          before = quote(before) unless before == false
          after  = quote(after)  unless after == false

          quote_enum_values(name, values, options).each do |value|
            reference = "BEFORE #{before}" unless before == false
            reference = "AFTER  #{after}"  unless after == false
            execute <<-SQL.squish
              ALTER TYPE #{quote_type_name(name)}
              ADD VALUE #{value} #{reference}
            SQL

            before = false
            after  = value
          end
        end

        # Returns all values that an enum type can have.
        def enum_values(name)
          select_values(<<-SQL.squish, 'SCHEMA')
            SELECT enumlabel FROM pg_enum
            WHERE enumtypid = #{quote(name)}::regtype::oid
            ORDER BY enumsortorder
          SQL
        end


        # Add the schema option when extracting table options
        def table_options(table_name)
          options = super

          if PostgreSQL.config.schemas.enabled
            table, schema = table_name.split('.').reverse
            if table.present? && schema.present? && schema != current_schema
              options[:schema] = schema
            end
          end

          if options[:options]&.start_with?('INHERITS (')
            options.delete(:options)

            tables = inherited_table_names(table_name)
            options[:inherits] = tables.one? ? tables.first : tables
          end

          options
        end

        # When dumping the schema we need to add all schemas, not only those
        # active for the current +schema_search_path+
        def quoted_scope(name = nil, type: nil)
          return super unless name.nil?

          scope = super
          global = scope[:schema].start_with?('ANY (')
          scope[:schema] = "ANY ('{#{user_defined_schemas.join(',')}}')"
          scope
        end

        # Fix the query to include the schema on tables names when dumping
        def data_source_sql(name = nil, type: nil)
          return super unless name.nil?

          super.sub('SELECT c.relname FROM', "SELECT n.nspname || '.' || c.relname FROM")
        end

        # Add schema and inherits as one of the valid options for table
        # definition
        def valid_table_definition_options
          super + [:schema, :inherits]
        end

        # Add proper support for schema load when using versioned commands
        def assume_migrated_upto_version(version)
          return super unless PostgreSQL.config.versioned_commands.enabled
          return super if (commands = pool.migration_context.migration_commands).empty?

          version = version.to_i
          migration_context = pool.migration_context
          migrated = migration_context.get_all_versions
          versions = migration_context.migrations.map(&:version)

          inserting = (versions - migrated).select { |v| v < version }
          inserting << version unless migrated.include?(version)
          return if inserting.empty?

          duplicated = inserting.tally.filter_map { |v, count| v if count > 1 }
          raise <<~MSG.squish if duplicated.present?
            Duplicate migration #{duplicated.first}.
            Please renumber your migrations to resolve the conflict.
          MSG

          VersionedCommands::SchemaTable.new(pool).create_table
          execute insert_versions_sql(inserting)
        end

        # Add proper support for schema load when using versioned commands
        def insert_versions_sql(versions)
          return super unless PostgreSQL.config.versioned_commands.enabled

          commands = pool.migration_context.migration_commands.select do |migration|
            versions.include?(migration.version)
          end

          return super if commands.empty?

          table = quote_table_name(VersionedCommands::SchemaTable.new(pool).table_name)

          sql = super(versions - commands.map(&:version))
          sql << "\nINSERT INTO #{table} (version, type, object_name) VALUES\n"
          sql << commands.map do |m|
            +"(#{quote(m.version)}, #{quote(m.type)}, #{quote(m.object_name)})"
          end.join(",\n")
          sql << ";"
          sql
        end

        private

          # Remove the schema from the sequence name
          def sequence_name_from_parts(table_name, column_name, suffix)
            super(table_name.split('.').last, column_name, suffix)
          end

          # Helper for supporting schema name in several methods
          def sanitize_name_with_schema(name, options)
            return name if (schema = options&.delete(:schema)).blank?
            Quoting::Name.new(schema.to_s, name.to_s)
          end

          def quote_enum_values(name, values, options)
            prefix = options[:prefix]
            prefix = name if prefix === true

            suffix = options[:suffix]
            suffix = name if suffix === true

            values.map! do |value|
              quote([prefix, value, suffix].compact.join('_'))
            end
          end

      end
    end
  end
end
