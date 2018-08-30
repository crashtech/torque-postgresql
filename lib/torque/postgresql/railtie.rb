module Torque
  module PostgreSQL
    # = Torque PostgreSQL Railtie
    class Railtie < Rails::Railtie # :nodoc:

      # Get information from the running rails app
      initializer 'torque-postgresql' do |app|
        Torque::PostgreSQL.config.eager_load = app.config.eager_load
      end

    end
  end
end
