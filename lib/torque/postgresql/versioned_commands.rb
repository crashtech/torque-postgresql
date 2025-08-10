# frozen_string_literal: true

require_relative 'versioned_commands/command_migration'
require_relative 'versioned_commands/migration_context'
require_relative 'versioned_commands/migrator'
require_relative 'versioned_commands/schema_table'

module Torque
  module PostgreSQL
    # Takes advantage of Rails migrations to create other sorts of
    # objects/commands that can also be versioned. Everything migrated will
    # still live within Migrations borders (i.e., the schema_migrations), but
    # the way they are handled and registered in the schema dumper is completely
    # different
    module VersionedCommands
      RAILS_APP = defined?(Rails.application.paths)
      NAME_MATCH = '"?((?:[_a-z0-9]+"?\."?)?[_a-z0-9]+)"?'

      class << self
        # Check if the type is current enabled
        def valid_type?(type)
          PostgreSQL.config.versioned_commands.types.include?(type.to_sym)
        end

        # Run the internal validations for the given type and content
        def validate!(type, content, name)
          method_name = :"validate_#{type}!"
          return send(method_name, content, name) if valid_type?(type)
          raise ArgumentError, "Unknown versioned command type: #{type}"
        end

        # Get the content of the command based on the type, name, and version
        def fetch_command(dirs, type, name, version)
          paths = Array.wrap(dirs).map { |d| "#{d}/**/*_#{type}_#{name}_v#{version}.sql" }
          files = Dir[*paths]
          return File.read(files.first) if files.one?

          raise ArgumentError, <<~MSG.squish if files.none?
            No previous version found for #{type} #{name}
            of version v#{version}.
          MSG

          raise ArgumentError, <<~MSG.squish if files.many?
            Multiple files found for #{type} #{name}
            of version v#{version}.
          MSG
        end

        # The regexp is dynamic due to the list of available types
        def filename_regexp
          @filename_regexp ||= begin
            types = PostgreSQL.config.versioned_commands.types
            Regexp.new([
              "\\A([0-9]+)_",
              "(create|update|remove)_",
              "(#{types.join('|')})_",
              "([_a-z0-9]*)",
              "_v([0-9]+)",
              "\\.?([_a-z0-9]*)?",
              "\\.sql\\z",
            ].join)
          end
        end

        private

          # Validate that the content of the command is correct
          def validate_function!(content, name)
            result = content.scan(Regexp.new([
              '^\s*CREATE\s+(OR\s+REPLACE)?\s*',
              "FUNCTION\\s+#{NAME_MATCH}",
            ].join, 'mi'))

            names = result.map(&:last).compact.uniq(&:downcase)
            raise ArgumentError, <<~MSG.squish if names.size > 1
              Multiple functions definition found.
            MSG

            raise ArgumentError, <<~MSG.squish unless result.all?(&:first)
              'OR REPLACE' is required for proper migration support.
            MSG

            fn_name = names.first.downcase.sub('.', '_')
            raise ArgumentError, <<~MSG.squish if fn_name != name.downcase
              Function name must match file name.
            MSG
          end

          # Validate that the content of the command is correct
          def validate_type!(content, name)
            creates = content.scan(Regexp.new(['^\s*CREATE\s+TYPE\s+', NAME_MATCH].join, 'mi'))
            drops = content.scan(Regexp.new([
              '^\s*DROP\s+TYPE\s+(IF\s+EXISTS)?\s*',
              NAME_MATCH,
            ].join, 'mi'))

            raise ArgumentError, <<~MSG.squish if creates.size > 1
              More than one type definition found.
            MSG

            raise ArgumentError, <<~MSG.squish if drops.size > 1
              More than one type drop found.
            MSG

            raise ArgumentError, <<~MSG.squish if drops.empty?
              'DROP TYPE' is required for proper migration support.
            MSG

            create_name = creates.first.last.downcase
            raise ArgumentError, <<~MSG.squish if drops.first.last.downcase != create_name
              Drop does not match create.
            MSG

            create_name = create_name.sub('.', '_')
            raise ArgumentError, <<~MSG.squish if create_name != name.downcase
              Type name must match file name.
            MSG
          end

          # Validate that the content of the command is correct
          def validate_view!(content, name)
            result = content.scan(Regexp.new([
              '^\s*CREATE\s+(OR\s+REPLACE)?\s*',
              '((?:TEMP|TEMPORARY|MATERIALIZED)\s+)?',
              '(?:RECURSIVE\s+)?',
              "VIEW\\s+#{NAME_MATCH}",
            ].join, 'mi'))

            raise ArgumentError, <<~MSG.squish if result.empty?
              Missing or invalid view definition.
            MSG

            raise ArgumentError, <<~MSG.squish if result.size > 1
              More than one view definition found.
            MSG

            with_replace, opt, view_name = result.first
            if opt&.strip == 'MATERIALIZED'
              raise ArgumentError, <<~MSG.squish if with_replace.present?
                Materialized view does not support 'OR REPLACE'.
              MSG

              with_drop = "DROP MATERIALIZED VIEW IF EXISTS #{view_name};"
              raise ArgumentError, <<~MSG.squish unless content.include?(with_drop)
                'DROP MATERIALIZED VIEW IF EXISTS' is required for proper migration support.
              MSG
            else
              raise ArgumentError, <<~MSG.squish if with_replace.blank?
                'OR REPLACE' is required for proper migration support.
              MSG
            end

            view_name = view_name.downcase.sub('.', '_')
            raise ArgumentError, <<~MSG.squish if view_name != name.downcase
              View name must match file name.
            MSG
          end
      end
    end
  end
end
