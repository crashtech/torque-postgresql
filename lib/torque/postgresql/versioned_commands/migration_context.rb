# frozen_string_literal: true

module Torque
  module PostgreSQL
    class IllegalCommandTypeError < ActiveRecord::MigrationError
      def initialize(file)
        super(<<~MSG.squish)
          Illegal name for command file '#{file}'. Commands are more strict and require
          the version, one of create, update, or remove, type of object, name
          and operation version to be present in the filename.
          (e.g. 20250101010101_create_function_my_function_v1.sql)
        MSG
      end
    end

    module VersionedCommands
      module MigrationContext
        InvalidMigrationTimestampError = ActiveRecord::InvalidMigrationTimestampError
        PGAdapter = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter

        def migrations
          return super unless running_for_pg?

          commands = command_files.map do |file|
            version, op, type, name, op_version, scope = parse_command_filename(file)
            raise IllegalCommandTypeError.new(file) unless version
            if validate_timestamp? && !valid_migration_timestamp?(version)
              raise InvalidMigrationTimestampError.new(version, [op, type, name, op_version].join('_'))
            end

            version = version.to_i
            CommandMigration.new(file, version, op, type, name, op_version.to_i, scope)
          end

          super.concat(commands).sort_by(&:version)
        end

        def migrations_status
          return super unless running_for_pg?
          db_list = schema_migration.normalized_versions

          commands = command_files.map do |file|
            version, op, type, name, op_version, scope = parse_command_filename(file)
            raise IllegalCommandTypeError.new(file) unless version
            if validate_timestamp? && !valid_migration_timestamp?(version)
              raise InvalidMigrationTimestampError.new(version, [op, type, name, op_version].join('_'))
            end

            version = schema_migration.normalize_migration_number(version)
            status = db_list.delete(version) ? "up" : "down"
            [status, version, "#{op.capitalize} #{type.capitalize} #{name}#{scope} (v#{op_version})"]
          end

          (commands + super).uniq(&:second).sort_by(&:second)
        end

        def migration_commands
          migrations.select { |m| m.is_a?(VersionedCommands::CommandMigration) }
        end

        private

          # Checks if the current migration context is running for PostgreSQL
          def running_for_pg?
            connection_pool.db_config.adapter_class <= PGAdapter
          end

          # Get the list of all versioned command files
          def command_files
            paths = Array(migrations_paths)
            Dir[*paths.flat_map { |path| "#{path}/**/[0-9]*_*.sql" }]
          end

          # Commands are more strict with the filename format
          def parse_command_filename(filename)
            File.basename(filename).scan(VersionedCommands.filename_regexp).first
          end
      end

      ActiveRecord::MigrationContext.prepend(MigrationContext)
    end
  end
end
