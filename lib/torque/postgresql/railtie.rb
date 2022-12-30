# frozen_string_literal: true

module Torque
  module PostgreSQL
    # = Torque PostgreSQL Railtie
    class Railtie < Rails::Railtie # :nodoc:

      # Get information from the running rails app
      initializer 'torque-postgresql' do |app|
        torque_config = Torque::PostgreSQL.config
        torque_config.eager_load = app.config.eager_load

        # Include enum on ActiveRecord::Base so it can have the correct enum
        # initializer
        Torque::PostgreSQL::Attributes::Enum.include_on(ActiveRecord::Base)
        Torque::PostgreSQL::Attributes::EnumSet.include_on(ActiveRecord::Base)
        Torque::PostgreSQL::Attributes::Period.include_on(ActiveRecord::Base)

        # Setup belongs_to_many association
        ActiveRecord::Base.belongs_to_many_required_by_default = torque_config.associations
          .belongs_to_many_required_by_default

        # Define a method to find enumaerators based on the namespace
        torque_config.enum.namespace.define_singleton_method(:const_missing) do |name|
          Torque::PostgreSQL::Attributes::Enum.lookup(name)
        end

        # Define a helper method to get a sample value
        torque_config.enum.namespace.define_singleton_method(:sample) do |name|
          Torque::PostgreSQL::Attributes::Enum.lookup(name).sample
        end

        # Define the exposed constant for both types of auxiliary statements
        if torque_config.auxiliary_statement.exposed_class.present?
          *ns, name = torque_config.auxiliary_statement.exposed_class.split('::')
          base = ns.present? ? Object.const_get(ns.join('::')) : Object
          base.const_set(name, Torque::PostgreSQL::AuxiliaryStatement)

          *ns, name = torque_config.auxiliary_statement.exposed_recursive_class.split('::')
          base = ns.present? ? Object.const_get(ns.join('::')) : Object
          base.const_set(name, Torque::PostgreSQL::AuxiliaryStatement::Recursive)
        end
      end
    end
  end
end
