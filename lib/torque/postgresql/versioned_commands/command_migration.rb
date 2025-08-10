# frozen_string_literal: true

module Torque
  module PostgreSQL
    module VersionedCommands
      module Migration
        def initialize(*args)
          @command = args.pop
          super(*args)
        end

        # Prepare the description based on the direction
        def migrate(direction)
          @description = description_for(direction)
          super
        end

        # Uses the command to execute the proper action
        def exec_migration(conn, direction)
          @connection = conn
          direction == :up ? @command.up : @command.down
        ensure
          @connection = nil
          @execution_strategy = nil
        end

        # Better formatting of the output
        def announce(message)
          action, result = @description

          title = [
            @command.type.capitalize,
            @command.object_name,
            "v#{@command.op_version}"
          ].join(' ')

          timing = message.split(' ', 2).second
          action = "#{result} #{timing}" if timing.present?
          text = "#{@command.version} #{title}: #{action}"
          length = [0, 75 - text.length].max

          write "== %s %s" % [text, "=" * length]
        end

        # Produces a nice description of what is being done
        def description_for(direction)
          base = @command.op.chomp('e') if direction == :up
          base ||=
            case @command.op
            when 'create' then 'dropp'
            when 'update' then 'revert'
            when 'remove' then 're-creat'
            end

          ["#{base}ing", "#{base}ed"]
        end

        # Print the command and then execute it
        def execute(command)
          write "-- #{command.gsub(/(?<!\A)^/, '   ').gsub(/[\s\n]*\z/, '')}"
          execution_strategy.execute(command)
        end
      end

      CommandMigration = Struct.new(*%i[filename version op type object_name op_version scope]) do
        delegate :execute, to: '@migration'

        def initialize(filename, *args)
          super(File.expand_path(filename), *args)
          @migration = nil
        end

        # Rails uses this to avoid duplicate migrations
        def name
          "#{op}_#{type}_#{object_name}_v#{op_version}"
        end

        # There is no way to setup this, so it is always false
        def disable_ddl_transaction
          false
        end

        # Down is more complicated, then this just starts separating the logic
        def migrate(direction)
          @migration = ActiveRecord::Migration.allocate
          @migration.extend(Migration)
          @migration.send(:initialize, name, version, self)
          @migration.migrate(direction)
        ensure
          @migration = nil
        end

        # Simply executes the underlying command
        def up
          content = File.read(filename)
          VersionedCommands.validate!(type, content, object_name)
          execute content
        end

        # Find the previous command and executes it
        def down
          return drop if op_version == 1
          dirs = @migration.pool.migrations_paths
          version = op_version - (op == 'remove' ? 0 : 1)
          execute VersionedCommands.fetch_command(dirs, type, object_name, version)
        end

        # Drops the type created
        def drop
          method_name = :"drop_#{type}"
          return send(method_name) if VersionedCommands.valid_type?(type)
          raise ArgumentError, "Unknown versioned command type: #{type}"
        end

        private

          # Drop all functions all at once
          def drop_function
            definitions = File.read(filename).scan(Regexp.new([
              "FUNCTION\\s+#{NAME_MATCH}",
              '\s*(\([_a-z0-9 ,]*\))?',
            ].join, 'mi'))

            functions = definitions.map(&:join).join(', ')
            execute "DROP FUNCTION #{functions};"
          end

          # Drop the type
          def drop_type
            name = File.read(filename).scan(Regexp.new("TYPE\\s+#{NAME_MATCH}", 'mi'))
            execute "DROP TYPE #{name.first.first};"
          end

          # Drop view or materialized view
          def drop_view
            mat, name = File.read(filename).scan(Regexp.new([
              '(MATERIALIZED)?\s+(?:RECURSIVE\s+)?',
              "VIEW\\s+#{NAME_MATCH}",
            ].join, 'mi')).first

            execute "DROP#{' MATERIALIZED' if mat.present?} VIEW #{name};"
          end
      end
    end
  end
end
