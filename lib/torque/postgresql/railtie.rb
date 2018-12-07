module Torque
  module PostgreSQL
    # = Torque PostgreSQL Railtie
    class Railtie < Rails::Railtie # :nodoc:

      # Get information from the running rails app
      initializer 'torque-postgresql' do |app|
        Torque::PostgreSQL.config.eager_load = app.config.eager_load

        # Include enum on ActiveRecord::Base so it can have the correct enum
        # initializer
        Torque::PostgreSQL::Attributes::Enum.include_on(ActiveRecord::Base)

        # Define a method to find yet to define constants
        Torque::PostgreSQL.config.enum.namespace.define_singleton_method(:const_missing) do |name|
          Torque::PostgreSQL::Attributes::Enum.lookup(name)
        end

        # Define a helper method to get a sample value
        Torque::PostgreSQL.config.enum.namespace.define_singleton_method(:sample) do |name|
          Torque::PostgreSQL::Attributes::Enum.lookup(name).sample
        end
      end

    end
  end
end
