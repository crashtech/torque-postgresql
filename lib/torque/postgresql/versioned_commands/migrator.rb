# frozen_string_literal: true

module Torque
  module PostgreSQL
    module VersionedCommands
      module Migrator
        def execute_migration_in_transaction(migration)
          @versioned_command = versioned_command?(migration) && migration
          super
        ensure
          @versioned_command = false
        end

        def record_version_state_after_migrating(version)
          return super if (command = @versioned_command) == false

          @versioned_table ||= VersionedCommands::SchemaTable.new(connection.pool)
          @versioned_counter ||= @versioned_table.count

          if down?
            @versioned_counter -= 1
            @versioned_table.delete_version(command)
            @versioned_table.drop_table if @versioned_counter.zero?
          else
            @versioned_table.create_table if @versioned_counter.zero?
            @versioned_table.create_version(command)
            @versioned_counter += 1
          end
        end

        def versioned_command?(migration)
          migration.is_a?(VersionedCommands::CommandMigration)
        end
      end

      ActiveRecord::Migrator.prepend(Migrator)
    end
  end
end
