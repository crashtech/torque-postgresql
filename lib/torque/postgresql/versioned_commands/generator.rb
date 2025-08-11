# frozen_string_literal: true

require 'rails/generators/base'
require 'rails/generators/active_record/migration'

module Torque
  module PostgreSQL
    module VersionedCommands
      module Generator
        TEMPLATES_PATH = '../../../generators/torque/templates'

        attr_reader :file_name

        def self.included(base)
          type = base.name.demodulize.chomp('Generator').underscore

          base.send(:source_root, File.expand_path(TEMPLATES_PATH, __dir__))
          base.include(ActiveRecord::Generators::Migration)

          base.instance_variable_set(:@type, type)
          base.instance_variable_set(:@desc, <<~DESC.squish)
            Generates a migration for creating, updating, or removing a #{type}.
          DESC

          base.class_option :operation, type: :string, aliases: %i(--op),
            desc: 'The name for the operation'

          base.argument :name, type: :string,
            desc: "The name of the #{type}"
        end

        def type
          self.class.instance_variable_get(:@type)
        end

        def create_migration_file
          version = count_object_entries
          operation = options[:operation] || (version == 0 ? 'create' : 'update')
          @file_name = "#{operation}_#{type}_#{name.underscore}_v#{version + 1}"

          validate_file_name!
          migration_template "#{type}.sql.erb", File.join(db_migrate_path, "#{file_name}.sql")
        end

        def count_object_entries
          Dir.glob("#{db_migrate_path}/*_#{type}_#{name.underscore}_v*.sql").size
        end

        def validate_file_name!
          unless /^[_a-z0-9]+$/.match?(file_name)
            raise ActiveRecord::IllegalMigrationNameError.new(file_name)
          end
        end
      end
    end
  end
end
