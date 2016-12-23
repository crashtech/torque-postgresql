module Torque
  module PostgreSQL
    include ActiveSupport::Configurable

    # Allow nested configurations
    config.define_singleton_method(:nested) do |name, &block|
      klass = Class.new(ActiveSupport::Configurable::Configuration).new
      block.call(klass) if block
      send("#{name}=", klass)
    end

    # Configure ENUM features
    config.nested(:enum) do |enum|

      # Indicates if the enum features on ActiveRecord::Base should be initiated
      # automatically or not
      enum.initializer = false

      # Specify the namespace of each enum type of value
      enum.namespace = ::Object.const_set('Enum', Module.new)

    end

    # Configure Composite features
    config.nested(:composite) do |composite|

      # Indicates if the composite features on ActiveRecord::Base should be
      # initiated automatically or not
      composite.initializer = true

      # Specify the namespace of composite ActiveRecord::Base auto-generated
      # classes
      composite.namespace = ::Object

      # Specify the name of the constant where users can shortcut the Base class
      # through ActiveRecord
      composite.shortcut = 'Composite'

    end

  end
end
