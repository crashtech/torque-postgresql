module Torque
  module PostgreSQL
    module Adapter
      module SchemaStatements

        TableDefinition = ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition

        # Drops a type.
        def drop_type(name, options = {})
          force = options.fetch(:force, '').upcase
          check = 'IF EXISTS' if options.fetch(:check, true)
          execute <<-SQL
            DROP TYPE #{check}
            #{quote_type_name(name, options[:schema])} #{force}
          SQL
        end

        # Renames a type.
        def rename_type(type_name, new_name)
          execute <<-SQL
            ALTER TYPE #{quote_type_name(type_name)}
            RENAME TO #{Quoting::Name.new(nil, new_name.to_s).quoted}
          SQL
        end

        # Creates a new PostgreSQL enumerator type
        #
        # Example:
        #   create_enum 'status', ['foo', 'bar']
        #   create_enum 'status', ['foo', 'bar'], prefix: true
        #   create_enum 'status', ['foo', 'bar'], suffix: 'test'
        #   create_enum 'status', ['foo', 'bar'], force: true
        def create_enum(name, values, options = {})
          drop_type(name, options) if options[:force]
          execute <<-SQL
            CREATE TYPE #{quote_type_name(name, options[:schema])} AS ENUM
            (#{quote_enum_values(name, values, options).join(', ')})
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
            execute <<-SQL
              ALTER TYPE #{quote_type_name(name, options[:schema])}
              ADD VALUE #{value} #{reference}
            SQL

            before = false
            after  = value
          end
        end

        # Returns all values that an enum type can have.
        def enum_values(name)
          select_values("SELECT unnest(enum_range(NULL::#{name}))")
        end

        # Rewrite the method that creates tables to easily accept extra options
        def create_table(table_name, **options, &block)
          td = create_table_definition(table_name, **options)
          options[:id] = false if td.inherited_id?
          options[:temporary] = td

          super table_name, **options, &block
        end

        private

          # This waits for the second call to really return the table definition
          def create_table_definition(*args, **options) # :nodoc:
            if !args.second.kind_of?(TableDefinition)
              TableDefinition.new(*args, **options)
            else
              args.second
            end
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
