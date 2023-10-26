# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module SchemaStatements

        TableDefinition = ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition

        # Create a new schema
        def create_schema(name, options = {})
          drop_schema(name, options) if options[:force]

          check = 'IF NOT EXISTS' if options.fetch(:check, true)
          execute("CREATE SCHEMA #{check} #{quote_schema_name(name.to_s)}")
        end

        # Drop an existing schema
        def drop_schema(name, options = {})
          force = options.fetch(:force, '').upcase
          check = 'IF EXISTS' if options.fetch(:check, true)
          execute("DROP SCHEMA #{check} #{quote_schema_name(name.to_s)} #{force}")
        end

        # Drops a type.
        def drop_type(name, options = {})
          force = options.fetch(:force, '').upcase
          check = 'IF EXISTS' if options.fetch(:check, true)
          execute <<-SQL.squish
            DROP TYPE #{check}
            #{quote_type_name(name, options[:schema])} #{force}
          SQL
        end

        # Renames a type.
        def rename_type(type_name, new_name, options = {})
          execute <<-SQL.squish
            ALTER TYPE #{quote_type_name(type_name, options[:schema])}
            RENAME TO #{Quoting::Name.new(nil, new_name.to_s).quoted}
          SQL
        end

        # Changes the enumerator by adding new values
        #
        # Example:
        #   add_enum_values 'status', ['baz']
        #   add_enum_values 'status', ['baz'], before: 'bar'
        #   add_enum_values 'status', ['baz'], after: 'foo'
        #   add_enum_values 'status', ['baz'], prepend: true
        def add_enum_values(name, values, options = {})
          before = options.fetch(:before, false)
          after  = options.fetch(:after,  false)

          before = enum_values(name).first if options.key? :prepend
          before = quote(before) unless before == false
          after  = quote(after)  unless after == false

          quote_enum_values(name, values, options).each do |value|
            reference = "BEFORE #{before}" unless before == false
            reference = "AFTER  #{after}"  unless after == false
            execute <<-SQL.squish
              ALTER TYPE #{quote_type_name(name, options[:schema])}
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

        # Rewrite the method that creates tables to easily accept extra options
        def create_table(table_name, **options, &block)
          table_name = "#{options[:schema]}.#{table_name}" if options[:schema].present?

          options[:id] = false if options[:inherits].present? &&
            options[:primary_key].blank? && options[:id].blank?

          super table_name, **options.except(:schema), &block
        end

        # Simply add the schema to the table name when changing a table
        def change_table(table_name, **options)
          table_name = "#{options[:schema]}.#{table_name}" if options[:schema].present?
          super table_name, **options
        end

        # Simply add the schema to the table name when dropping a table
        def drop_table(table_name, **options)
          table_name = "#{options[:schema]}.#{table_name}" if options[:schema].present?
          super table_name, **options
        end

        # Add the schema option when extracting table options
        def table_options(table_name)
          parts = table_name.split('.').reverse
          return super unless parts.size == 2 && parts[1] != 'public'

          (super || {}).merge(schema: parts[1])
        end

        # When dumping the schema we need to add all schemas, not only those
        # active for the current +schema_search_path+
        def quoted_scope(name = nil, type: nil)
          return super unless name.nil?

          super.merge(schema: "ANY ('{#{user_defined_schemas.join(',')}}')")
        end

        # Fix the query to include the schema on tables names when dumping
        def data_source_sql(name = nil, type: nil)
          return super unless name.nil?

          super.sub('SELECT c.relname FROM', "SELECT n.nspname || '.' || c.relname FROM")
        end

        private

          # Remove the schema from the sequence name
          def sequence_name_from_parts(table_name, column_name, suffix)
            super(table_name.split('.').last, column_name, suffix)
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
