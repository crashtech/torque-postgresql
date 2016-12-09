# TODO Maybe use the rails application configuration class
module Torque
  module Postgresql

    class << self

      def config(&block)
        @config ||= Config.new
        @config.setup(&block) if block_given?
        @config
      end

      alias :configure :config

    end

    class Config

      DEFAULT_ENUM_INITIALIZER = true
      DEFAULT_ENUM_VALUES_TYPE = Array

      SETTINGS = [:enum_initializer, :enum_values_type]

      def setup
        yield self if block_given?
      end

      # Generates all methods needed for configurations
      SETTINGS.each do |setting|
        name = "@#{setting}"

        # Getter
        define_method setting do
          if instance_variable_defined? name
            instance_variable_get name
          else
            send "#{setting}=", :default
          end
        end

        # Setter
        define_method "#{setting}=" do |value|
          value = Config.const_get("DEFAULT_#{setting.to_s.upcase}") if value == :default
          instance_variable_set name, value
        end
      end

    end

  end
end
