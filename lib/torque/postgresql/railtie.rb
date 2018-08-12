module Torque
  module PostgreSQL
    # = Torque PostgreSQL Railtie
    class Railtie < Rails::Railtie # :nodoc:

      # Eger load PostgreSQL namespace
      config.eager_load_namespaces << Torque::PostgreSQL

      # Get information from the running rails app
      runner do |app|
        Torque::PostgreSQL.config.eager_load = app.config.eager_load
      end

    end
  end
end
