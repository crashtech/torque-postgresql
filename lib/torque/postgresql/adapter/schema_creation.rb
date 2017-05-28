module Torque
  module PostgreSQL
    module Adapter
      module SchemaCreation

        # Redefine original table creation command to ensure PostgreSQL standard
        def visit_TableDefinition(o)
          create_sql = "CREATE#{' TEMPORARY' if o.temporary}"
          create_sql << " TABLE #{quote_table_name(o.name)}"

          statements = o.columns.map{ |c| accept c }
          statements << accept(o.primary_keys) if o.primary_keys

          if supports_indexes_in_create?
            statements.concat(o.indexes.map do |column_name, options|
              index_in_create(o.name, column_name, options)
            end)
          end

          if supports_foreign_keys?
            statements.concat(o.foreign_keys.map do |to_table, options|
              foreign_key_in_create(o.name, to_table, options)
            end)
          end

          if o.as
            create_sql << " AS #{@conn.to_sql(o.as)}"
          else
            create_sql << " (#{statements.join(', ')})"
            add_table_options!(create_sql, table_options(o))

            if o.inherits.present?
              tables = o.inherits.map(&method(:quote_table_name))
              create_sql << " INHERITS ( #{tables.join(' , ')} )"
            end
          end

          create_sql
        end

      end

      ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaCreation.prepend SchemaCreation
    end
  end
end
