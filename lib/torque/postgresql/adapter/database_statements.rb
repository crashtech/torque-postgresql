module Torque
  module PostgreSQL
    module Adapter
      module DatabaseStatements

        EXTENDED_DATABASE_TYPES = %i(enum composite interval)

        # Check if a given type is valid.
        def valid_type?(type)
          super || extended_types.include?(type)
        end

        # Get the list of extended types
        def extended_types
          EXTENDED_DATABASE_TYPES
        end

        # Returns true if type exists.
        def type_exists?(name)
          user_defined_types.key? name.to_s
        end
        alias data_type_exists? type_exists?

        # Drops a type.
        def drop_type(name, options = {})
          force = options.fetch(:force, '').upcase
          check = 'IF EXISTS' if options.fetch(:check, true)
          execute "DROP TYPE #{check} #{quote_type_name(name)} #{force}"
        end

        # Renames a type.
        def rename_type(type_name, new_name)
          execute <<-SQL
            ALTER TYPE #{quote_type_name(type_name)}
            RENAME TO #{quote_type_name(new_name)}
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
            CREATE TYPE #{quote_type_name(name)} AS ENUM
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
            execute "ALTER TYPE #{quote_type_name(name)} ADD VALUE #{value} #{reference}"

            before = false
            after  = value
          end
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
          td = create_composite_type_definition type_name, options[:as]

          yield td if block_given?

          if options[:force] && type_exists?(type_name)
            drop_type(type_name, options)
          end

          execute schema_creation.accept td
        end

        # Returns all values that an enum type can have.
        def enum_values(name)
          select_values("SELECT unnest(enum_range(NULL::#{name}))")
        end

        # Returns the list of all column definitions for a composite type.
        def composite_columns(type_name) # :nodoc:
          type_name = type_name.to_s
          column_definitions(type_name).map do |column_name, type, default, notnull, oid, fmod, collation, comment|
            oid = oid.to_i
            fmod = fmod.to_i
            type_metadata = fetch_type_metadata(column_name, type, oid, fmod)
            default_value = extract_value_from_default(default)
            default_function = extract_default_function(default_value, default)
            new_composite_column(column_name, default_value, type_metadata, !notnull, type_name, default_function, collation, comment: comment.presence)
          end
        end

        # Add the composite types to be loaded too.
        def load_additional_types(type_map, oids = nil)
          super

          filter = "AND     a.typelem::integer IN (%s)" % oids.join(", ") if oids

          query = <<-SQL
            SELECT      a.typelem AS oid, t.typname, t.typelem, t.typdelim, t.typbasetype
            FROM        pg_type t
            INNER JOIN  pg_type a ON (a.oid = t.typarray)
            LEFT JOIN   pg_catalog.pg_namespace n ON n.oid = t.typnamespace
            WHERE       n.nspname NOT IN ('pg_catalog', 'information_schema')
            AND     t.typtype = 'c'
            #{filter}
            AND     NOT EXISTS(
                      SELECT 1 FROM pg_catalog.pg_type el
                        WHERE el.oid = t.typelem AND el.typarray = t.oid
                      )
            AND     (t.typrelid = 0 OR (
                      SELECT c.relkind = 'c' FROM pg_catalog.pg_class c
                        WHERE c.oid = t.typrelid
                      ))
          SQL

          execute_and_clear(query, 'SCHEMA', []) do |records|
            records.each do |row|
              type =  Adapter::OID::Composite.new(row['typname'], row['typdelim'])
              type_map.register_type row['oid'].to_i, type
              type_map.alias_type row['typname'], row['oid']
            end
          end
        end

        # Gets a list of user defined types.
        # You can even choose the +typcategory+ filter
        def user_defined_types(category = nil)
          category_condition = "AND     typtype = '#{category}'" unless category.nil?
          select_all(<<-SQL).rows.to_h
            SELECT      t.typname AS name,
                        CASE t.typtype
                        WHEN 'e' THEN 'enum'
                        WHEN 'c' THEN 'composite'
                        END AS type
            FROM        pg_type t
            LEFT JOIN   pg_catalog.pg_namespace n ON n.oid = t.typnamespace
            WHERE       n.nspname NOT IN ('pg_catalog', 'information_schema')
            #{category_condition}
            AND     NOT EXISTS(
                      SELECT 1 FROM pg_catalog.pg_type el
                        WHERE el.oid = t.typelem AND el.typarray = t.oid
                      )
            AND     (t.typrelid = 0 OR (
                      SELECT c.relkind = 'c' FROM pg_catalog.pg_class c
                        WHERE c.oid = t.typrelid
                      ))
            ORDER BY    t.typtype DESC
          SQL
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
