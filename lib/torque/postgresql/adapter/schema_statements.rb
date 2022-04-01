# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module SchemaStatements

        TableDefinition = ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition

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
        def rename_type(type_name, new_name)
          execute <<-SQL.squish
            ALTER TYPE #{quote_type_name(type_name)}
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
          options[:id] = false if options[:inherits].present? &&
            options[:primary_key].blank? && options[:id].blank?

          super table_name, **options, &block
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
    end
  end
end
