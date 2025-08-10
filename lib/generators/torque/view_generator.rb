# frozen_string_literal: true

require 'torque/postgresql/versioned_commands/generator'

module Torque
  module Generators
    class ViewGenerator < Rails::Generators::Base
      include Torque::PostgreSQL::VersionedCommands::Generator

      class_option :materialized, type: :boolean, aliases: %i(--m), default: false,
        desc: 'Use materialized view instead of regular view'

      alias create_view_file create_migration_file
    end
  end
end
