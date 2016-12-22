module Torque
  module PostgreSQL
    module Adapter
      module SchemaStatements

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

        # Creates a new composite type with the name +type_name+. +type_name+
        # may either be a String or a Symbol.
        #
        # There are two ways to work with #create_composite_type. You can use
        # the block form or the regular form, like this:
        #
        # === Block form
        #
        #   # create_composite_type() passes a CompositeTypeDefinition object
        #   # to the block. This form will not only create the type, but also
        #   # columns for it.
        #
        #   create_composite_type(:address) do |t|
        #     t.column :street, :string, limit: 60
        #     # Other fields here
        #   end
        #
        # === Block form, with shorthand
        #
        #   # You can also use the column types as method calls, rather than
        #   # calling the column method.
        #   create_composite_type(:address) do |t|
        #     t.string :street, limit: 60
        #     # Other fields here
        #   end
        #
        # === Regular form
        #
        #   # Creates a type called 'address' with no columns.
        #   create_composite_type(:address)
        #   # Add a column to 'address'.
        #   add_composite_column(:address, :street, :string, {limit: 60})
        #
        # The +options+ hash can include the following keys:
        # [<tt>:force</tt>]
        #   Set to true to drop the type before creating it.
        #   Set to +:cascade+ to drop dependent objects as well.
        #   Defaults to false.
        # [<tt>:as</tt>]
        #   SQL to use to generate the composite type. When this option is used,
        #   the block is ignored
        #
        # See also CompositeTypeDefinition#column for details on how to create
        # columns.
        def create_composite_type(type_name, **options)
          td = create_composite_type_definition type_name, options, options[:as]

          yield td if block_given?

          if options[:force] && type_exists?(type_name)
            drop_type(type_name, options)
          end

          execute schema_creation.accept td
        end

        private

          def quote_enum_values(name, values, options)
            prefix = options[:prefix]
            prefix = name if prefix === true

            suffix = options[:suffix]
            suffix = name if suffix === true

            values.map! do |value|
              quote([prefix, value, suffix].compact.join('_'))
            end
          end

          def create_composite_type_definition(*args)
            CompositeTypeDefinition.new(*args)
          end

          def new_composite_column(*args) # :nodoc:
            CompositeColumn.new(*args)
          end

      end
    end
  end
end
