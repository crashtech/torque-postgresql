module Torque
  module Postgresql
    module Migration

      class CompositeOID < ActiveModel::Type::Value
        attr_reader :delim, :columns

        def initialize(delim, columns)
          @delim   = delim
          @columns = columns
        end

        def type
          :composite
        end

        def type_cast_for_schema(value)
          "ROW(#{value.map(&:inspect).join(',')})"
        end

        def cast_value(value)
          return value unless value.is_a?(::String)
          value = value.split(@delim, -1)

          columns.each_with_index do |column, idx|
            column.cast_value value[idx]
          end
        end

        def serialize(value)
          return unless value.is_a?(::Array)
          Data.new(value.each_with_index.map do |value, idx|
            column[idx].serialize(value)
          end.join(','))
        end

        def ==(other)
          other.is_a?(CompositeOID) &&
            other.columns == columns
        end

        def map(value)
          value.map
        end

        class Data # :nodoc:
          def initialize(value)
            @value = value
          end

          def to_s
            @value
          end
        end

      end

      class CompositeTypeDefinition < Connector::TableDefinition
        include Connector::ColumnMethods
        include EnumMethods

        undef :indexes, :indexes=, :temporary, :foreign_keys, :comment
        undef :primary_keys, :index, :foreign_key, :timestamps

        def initialize(name, options = nil, as = nil)
          @columns_hash = {}
          @options = options
          @as = as
          @name = name
        end

      end

      class CompositeColumn < ActiveRecord::ConnectionAdapters::PostgreSQLColumn
        attr_reader :type_name

        undef :table_name

        def initialize(name, default, sql_type_metadata = nil, null = true,
                       type_name = nil, default_function = nil, collation = nil,
                       comment: nil)
          @name = name.freeze
          @type_name = type_name
          @sql_type_metadata = sql_type_metadata
          @null = null
          @default = default
          @default_function = default_function
          @collation = collation
          @comment = comment
        end

        protected

          def attributes_for_hash
            [
              self.class,
              name,
              default,
              sql_type_metadata,
              null,
              type_name,default_function,
              collation
            ]
          end

      end

      module CompositeStatements

        def self.included(base)
          base.class_eval do
            alias original_load_additional_types load_additional_types

            # Add the composite types to be loaded too.
            def load_additional_types(type_map, oids = nil)
              original_load_additional_types(type_map, oids)

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
                  columns = composite_types(row['typname'])
                  type = CompositeOID.new(row['typdelim'], columns)
                  type_map.register_type row['oid'].to_i, type
                  type_map.alias_type row['typname'], row['oid']
                end
              end
            end
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

        # Return the list of types that compose a user-defined type
        def composite_types(type_name)
          type_name = type_name.to_s
          column_definitions(type_name).map do |column_name, type, _, _, oid, fmod, *rest|
            get_oid_type(oid, fmod, column_name, type)
          end
        end

        private

          def create_composite_type_definition(*args)
            CompositeTypeDefinition.new(*args)
          end

          def new_composite_column(*args) # :nodoc:
            CompositeColumn.new(*args)
          end

      end

      module CompositeReversion

        # Records the creation of the composition to be reverted.
        def create_composite_type(*args, &block)
          record(:create_composite_type, args, &block)
        end

        # Inverts the creation of the composite type.
        def invert_create_composite_type(args)
          [:drop_type, [args.first]]
        end

      end

      module CompositeSchemaCreation
        delegate :quote_type_name, to: :@conn

        private

        def visit_CompositeTypeDefinition(o)
          create_sql = "CREATE TYPE #{quote_type_name(o.name)} "
          statements = o.columns.map { |c| accept c }

          create_sql << "AS (#{statements.join(', ')})" if statements.present?
          create_sql << "AS (#{@conn.to_sql(o.as)})" if o.as
          create_sql
        end

      end

      module CompositeMethods
        def composite(*args, **options)
          args.each do |name|
            type = options.fetch(:subtype, name)
            column(name, type, options)
          end
        end
      end

      module CompositeDumper
        private
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

      Dumper.send :include, CompositeDumper
      Adapter.send :include, CompositeStatements
      Reversion.send :include, CompositeReversion

      Connector::TableDefinition.send :include, CompositeMethods
      Connector::SchemaCreation.send :include, CompositeSchemaCreation

    end
  end
end
