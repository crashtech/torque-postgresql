# frozen_string_literal: true

module Torque
  module PostgreSQL
    module I18n

      # Adds extra suport to localize durations
      # This is a temporary solution, since 3600.seconds does not translate into
      # 1 hour
      def localize(locale, object, format = :default, options = {})
        return super unless object.is_a?(ActiveSupport::Duration)
        object.inspect
      end

    end

    ::I18n::Backend::Base.prepend I18n
  end
end
