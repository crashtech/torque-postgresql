# frozen_string_literal: true

require 'rails/generators/base'

module Torque
  module Generators
    class SkillGenerator < Rails::Generators::Base
      source_root File.expand_path('../../../skills', __dir__)

      desc 'Copies the torque-postgresql agent skill into .claude/skills'

      def copy_skill
        directory 'torque-postgresql', '.claude/skills/torque-postgresql'
      end
    end
  end
end
