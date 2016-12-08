module Torque
  module Postgresql
    module Migration

      module EnumStatements

        # Creates a new PostgreSQL enumerator type
        #
        # Example:
        #   create_enum 'status', ['foo', 'bar']
        #   create_enum 'status', ['foo', 'bar'], prefix: true
        #   create_enum 'status', ['foo', 'bar'], suffix: 'test'
        def create_enum(name, values, options = {})
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

        # Returns all values that an enum type can have.
        def enum_values(name)
          select_values("SELECT unnest(enum_range(NULL::#{name}))")
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

      end

      module EnumReversion

        # Records the creation of the enum to be reverted.
        def create_enum(*args, &block)
          record(:create_enum, args, &block)
        end

        # Inverts the creation of the enum.
        def invert_create_enum(args)
          [:drop_type, [args.first]]
        end

      end

      module EnumMethods
        def enum(*args, **options)
          args.each do |name|
            type = options.fetch(:type, name)
            column(name, type, options)
          end
        end
      end

      Adapter.send :include, EnumStatements
      Reversion.send :include, EnumReversion

      Connector::TableDefinition.send :include, EnumMethods

    end
  end
end
