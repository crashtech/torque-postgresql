module Torque
  module PostgreSQL
    module Adapter
      module SchemaCreation

        # Redefine original table creation command to ensure PostgreSQL standard
        def visit_TableDefinition(o)
          create_sql = +"CREATE#{table_modifier_in_create(o)} TABLE "
          create_sql << "IF NOT EXISTS " if o.if_not_exists
          create_sql << "#{quote_table_name(o.name)} "

          statements = o.columns.map { |c| accept c }
          statements << accept(o.primary_keys) if o.primary_keys

          if supports_indexes_in_create?
            statements.concat(o.indexes.map { |c, o| index_in_create(o.name, c, o) })
          end

          if supports_foreign_keys?
            statements.concat(o.foreign_keys.map { |fk| accept fk })
          end

          if respond_to?(:supports_check_constraints?) && supports_check_constraints?
            statements.concat(o.check_constraints.map { |chk| accept chk })
          end

          create_sql << "(#{statements.join(', ')})" \
            if statements.present? || o.inherits.present?

          add_table_options!(create_sql, o)

          if o.inherits.present?
            tables = o.inherits.map(&method(:quote_table_name))
            create_sql << " INHERITS ( #{tables.join(' , ')} )"
          end

          create_sql << " AS #{to_sql(o.as)}" if o.as
          create_sql
        end
      end

      ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaCreation.prepend SchemaCreation
    end
  end
end
