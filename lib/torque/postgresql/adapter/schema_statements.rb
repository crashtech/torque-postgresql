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

        # Creates a new composite type, with the columns being defined using
        # the same DSL as +create_table+, although limited to the type itself,
        # the size-related options, and no indexes or constraints
        #
        # Example:
        #   create_composite_type :address do |t|
        #     t.string  "street"
        #     t.integer "number"
        #   end
        def create_composite_type(name, options = {})
          td = create_composite_type_definition(name)
          yield td if block_given?

          validate_composite_type!(name, td)
          drop_type(name, force: options[:force], check: true, schema: options[:schema]) \
            if options[:force]

          columns = td.columns.map { |column| composite_column_definition(name, column) }
          type_name = sanitize_name_with_schema(name, options.dup)

          internal_exec_query(<<~SQL.squish, 'SCHEMA').tap { reload_type_map }
            CREATE TYPE #{quote_type_name(type_name)} AS (#{columns.join(', ')})
          SQL
        end

        # Changes an existing composite type, using the same DSL as
        # +change_table+, although limited to what a type supports
        #
        # Example:
        #   change_composite_type :address do |t|
        #     t.string 'zipcode'
        #     t.change 'number', :bigint
        #     t.remove 'city'
        #     t.rename 'street', 'road'
        #   end
        def change_composite_type(name, options = {})
          td = create_composite_type_definition(name)
          yield td

          validate_composite_type!(name, td)
          type_name = quote_type_name(sanitize_name_with_schema(name, options.dup))
          actions = composite_type_actions(name, td)

          execute("ALTER TYPE #{type_name} #{actions.join(', ')}") if actions.any?

          td.renames.each do |from, to|
            execute <<~SQL.squish
              ALTER TYPE #{type_name}
              RENAME ATTRIBUTE #{quote_column_name(from)} TO #{quote_column_name(to)}
            SQL
          end

          reset_composite_type(name)
        end

        # Adds a single column to an existing composite type
        def add_composite_column(type_name, column_name, type, options = {})
          options = options.dup
          schema = options.delete(:schema)

          td = create_composite_type_definition(type_name)
          td.column(column_name, type, **options)

          alter_composite_type(type_name, schema, composite_type_actions(type_name, td))
        end

        # Removes a single column of an existing composite type. The +type+ is
        # only needed to make the migration reversible
        def remove_composite_column(type_name, column_name, type = nil, options = {})
          action = "DROP ATTRIBUTE #{quote_column_name(column_name)}"
          alter_composite_type(type_name, options[:schema], [action])
        end

        # Changes the type of a single column of an existing composite type
        def change_composite_column(type_name, column_name, type, options = {})
          options = options.dup
          schema = options.delete(:schema)

          td = create_composite_type_definition(type_name)
          td.change(column_name, type, **options)

          alter_composite_type(type_name, schema, composite_type_actions(type_name, td))
        end

        # Renames a single column of an existing composite type
        def rename_composite_column(type_name, column_name, new_name, options = {})
          action = <<~SQL.squish
            RENAME ATTRIBUTE #{quote_column_name(column_name)}
            TO #{quote_column_name(new_name)}
          SQL

          alter_composite_type(type_name, options[:schema], [action])
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

        # Add composite_type as one of the valid options for column definition
        def valid_column_definition_options
          super + [:composite_type]
        end

        # Maps the composite type through its required option, mirroring how
        # enums are handled
        def type_to_sql(type, composite_type: nil, **options)
          return super(type, **options) unless type.to_s == 'composite'

          raise ArgumentError, <<~MSG.squish if composite_type.nil?
            composite_type is required for composite columns
          MSG

          sql = composite_type.to_s
          sql = "#{sql}[]" if options[:array]
          sql
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

          # A composite type is defined with the same DSL as a table, but only
          # its columns are taken into account
          def create_composite_type_definition(name)
            CompositeTypeDefinition.new(self, name)
          end

          # Runs a single set of changes over an existing composite type
          def alter_composite_type(name, schema, actions)
            type_name = quote_type_name(sanitize_name_with_schema(name, schema: schema))
            execute("ALTER TYPE #{type_name} #{actions.join(', ')}")
            reset_composite_type(name)
          end

          # Every addition, change, and removal that a composite type can batch
          # into a single statement. Renames are left out because PostgreSQL
          # does not allow them to be combined with other actions
          def composite_type_actions(name, td)
            adds = td.columns.map do |column|
              "ADD ATTRIBUTE #{composite_column_definition(name, column)}"
            end

            changes = td.changes.map do |column|
              quoted = quote_column_name(column.name)
              "ALTER ATTRIBUTE #{quoted} TYPE #{composite_column_type(name, column)}"
            end

            drops = td.removals.map { |name| "DROP ATTRIBUTE #{quote_column_name(name)}" }

            adds + changes + drops
          end

          # A composite type only holds columns, so anything else that the DSL
          # can produce is rejected
          def validate_composite_type!(name, td)
            raise ArgumentError, <<~MSG.squish if td.indexes.present?
              Unable to define the composite type "#{name}" because it does
              not support indexes.
            MSG
          end

          # Build a single column of a composite type
          def composite_column_definition(name, column)
            "#{quote_column_name(column.name)} #{composite_column_type(name, column)}"
          end

          # Resolve the type of a column, making sure that only supported
          # options were provided
          def composite_column_type(name, column)
            supported = %i[limit precision scale array enum_type composite_type]
            options = column.options.dup
            options.delete(:primary_key) unless options[:primary_key]

            unsupported = options.keys - supported
            raise ArgumentError, <<~MSG.squish if unsupported.present?
              Unable to define the composite type "#{name}" because the
              column "#{column.name}" contains unsupported options:
              #{unsupported.map(&:inspect).join(', ')}.
            MSG

            type_to_sql(column.type, **options.slice(*supported))
          end

          # Members loaded by the class that handles the type are no longer
          # valid once the type itself has changed
          def reset_composite_type(name)
            reload_type_map
            return unless PostgreSQL.config.composite.enabled

            Attributes::Composite.lookup(name.to_s.split('.').last).reset_columns!
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
