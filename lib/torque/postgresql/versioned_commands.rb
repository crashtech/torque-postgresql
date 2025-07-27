# frozen_string_literal: true

require_relative 'versioned_commands/migration_context'

module Torque
  module PostgreSQL
    # Takes advantage of Rails migrations to create other sorts of
    # objects/commands that can also be versioned. Everything migrated will
    # still live within Migrations borders (i.e., the schema_migrations), but
    # the way they are handled and registered in the schema dumper is completely
    # different
    module VersionedCommands
      Settings = Struct.new(:type, :drop, :options)

      CommandMigration = Struct.new(:file, :version, :op, :type, :object_name, :scope) do
        attr_reader :migration

        def initialize(file, *args)
          super(File.expand_path(file), *args)
          @migration = nil
        end

        # Rails uses this to avoid duplicate migrations
        def name
          "#{op}_#{type}_#{object_name}_#{version}"
        end

        # There is no way to setup this, so it is always false
        def disable_ddl_transaction
          false
        end

        # Down is more complicated, then this just starts separating the logic
        def migrate(direction)
          command = self

          title = "#{type.capitalize} #{object_name}"
          action = op == 'create' ? 'creating' : 'updating' if direction == :up
          action ||= op == 'create' ? 'dropping' : 'reverting'

          @migration = ActiveRecord::Migration.new(name, version)
          @migration.define_singleton_method(:exec_migration) do |conn, direction|
            @connection = conn
            direction == :up ? command.up : command.down
          ensure
            @connection = nil
            @execution_strategy = nil
          end

          @migration.define_singleton_method(:announce) do |message|
            timing = message.split(' ', 2).second
            action = "#{action[..-4]}ed #{timing}" if timing
            text = "#{version} #{title}: #{action}"
            length = [0, 75 - text.length].max
            write "== %s %s" % [text, "=" * length]
          end

          @migration.migrate(direction)
        end

        # Simply executes the underlying command
        def up
          migration.execution_strategy.execute(File.read(file))
        end

        # Find the previous command and executes it
        def down
          return drop if op == 'create'

          previous, version = previous_command
          raise ArgumentError, <<~MSG.squish if version.nil?
            No previous version found for #{type} '#{object_name}' from version #{version}.
          MSG

          migration.execution_strategy.execute(File.read(previous))
        end

        # Drops the type created
        def drop
          command = VersionedCommands.commands[type.pluralize.to_sym].drop
          raise ArgumentError, "No drop command registered for #{type}" unless command
          migration.execution_strategy.execute(format(command, name: object_name))
        end

        private

          def previous_command
            query = "#{File.dirname(file)}/*_#{type}_#{object_name}.sql"
            Dir.glob(query).reverse.each do |other|
              version = File.basename(other).split('_').first.to_i
              return [other, version] if version < self.version
            end
          end
      end

      RAILS_APP = defined?(Rails.application.paths)

      class << self

        # List of type of versioned commands handled
        def commands
          @commands ||= {}
        end

        # Register a new type of versioned command
        def register(type, drop_with:, options: {}, &block)
          type = type.to_s.pluralize.to_sym
          raise ArgumentError, <<~MSG.squish unless type =~ /\A[a-z_]+\z/
            Command type '#{type}' is invalid.
            It can contain only lowercase letters and underscores.
          MSG

          raise ArgumentError, <<~MSG.squish if commands.key?(type)
            Command type '#{type}' is already registered.
          MSG

          settings = commands[type] = Settings.new(type, drop_with, options)
          settings.class_eval(&block) if block_given?
          settings
        end

        # The regexp is dynamic due to the list of available types
        def filename_regexp
          @filename_regexp ||= Regexp.new([
            "\\A([0-9]+)_",
            "(create|update)_",
            "(#{commands.each_key.map { |type| type.to_s.singularize }.join('|')})_",
            "([_a-z0-9]*)",
            "\\.?([_a-z0-9]*)?",
            "\\.sql\\z",
          ].join)
        end

      end
    end
  end
end
