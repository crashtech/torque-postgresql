# frozen_string_literal: true

require 'torque/postgresql/versioned_commands/generator'

module Torque
  module Generators
    class TypeGenerator < Rails::Generators::Base
      include Torque::PostgreSQL::VersionedCommands::Generator

      alias create_type_file create_migration_file
    end
  end
end
