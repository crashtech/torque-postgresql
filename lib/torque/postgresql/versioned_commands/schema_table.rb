# frozen_string_literal: true

module Torque
  module PostgreSQL
    module VersionedCommands
      class SchemaTable
        attr_reader :arel_table

        def initialize(pool)
          @pool = pool
          @arel_table = ::Arel::Table.new(table_name)
        end

        def create_version(command)
          im = ::Arel::InsertManager.new(arel_table)
          im.insert(
            arel_table[primary_key] => command.version,
            arel_table['type'] => command.type,
            arel_table['object_name'] => command.object_name,
          )

          @pool.with_connection do |connection|
            connection.insert(im, "#{name} Create", primary_key, command.version)
          end
        end

        def delete_version(command)
          dm = ::Arel::DeleteManager.new(arel_table)
          dm.wheres = [arel_table[primary_key].eq(command.version.to_s)]

          @pool.with_connection do |connection|
            connection.delete(dm, "#{name} Destroy")
          end
        end

        def primary_key
          'version'
        end

        def name
          'Torque::PostgreSQL::VersionedCommand'
        end

        def table_name
          [
            ActiveRecord::Base.table_name_prefix,
            PostgreSQL.config.versioned_commands.table_name,
            ActiveRecord::Base.table_name_suffix,
          ].join
        end

        def create_table
          @pool.with_connection do |connection|
            return if connection.table_exists?(table_name)

            parent = @pool.schema_migration.table_name
            connection.create_table(table_name, inherits: parent) do |t|
              t.string :type, null: false, index: true
              t.string :object_name, null: false, index: true
            end
          end
        end

        def drop_table
          @pool.with_connection do |connection|
            connection.drop_table table_name, if_exists: true
          end
        end

        def count
          return 0 unless table_exists?

          sm = ::Arel::SelectManager.new(arel_table)
          sm.project(*FN.count(::Arel.star))

          @pool.with_connection do |connection|
            connection.select_value(sm, "#{self.class} Count")
          end
        end

        def table_exists?
          @pool.with_connection { |connection| connection.data_source_exists?(table_name) }
        end

        def versions_of(type)
          return [] unless table_exists?

          sm = ::Arel::SelectManager.new(arel_table)
          sm.project(arel_table['object_name'], FN.count(::Arel.star).as('version'))
          sm.where(arel_table['type'].eq(type.to_s))
          sm.group(arel_table['object_name'])
          sm.order(arel_table['object_name'].asc)

          @pool.with_connection do |connection|
            connection.select_rows(sm, "#{name} Load")
          end
        end
      end
    end
  end
end
