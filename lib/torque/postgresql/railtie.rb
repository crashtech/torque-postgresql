# frozen_string_literal: true

module Torque
  module PostgreSQL
    # = Torque PostgreSQL Railtie
    class Railtie < Rails::Railtie # :nodoc:
      # Get information from the running rails app
      initializer 'torque-postgresql' do |app|
        ActiveSupport.on_load(:active_record_postgresqladapter) do
          ActiveSupport.on_load(:active_record) do
            torque_config = Torque::PostgreSQL.config
            torque_config.eager_load = app.config.eager_load

            # TODO: Only load files that have their features enabled, like CTE

            ar_type = ActiveRecord::Type

            # Setup belongs_to_many association
            ActiveRecord::Base.belongs_to_many_required_by_default =
              torque_config.associations.belongs_to_many_required_by_default

            ## FN Helper
            if (mod = torque_config.expose_function_helper_on&.to_s)
              parent, _, name = mod.rpartition('::')
              parent.constantize.const_set(name, PostgreSQL::FN)
            end

            ## Schemas Enabled Setup
            if (config = torque_config.schemas).enabled
              require_relative 'adapter/schema_overrides'
            end

            ## CTE Enabled Setup
            if (config = torque_config.auxiliary_statement).enabled
              require_relative 'auxiliary_statement'
              require_relative 'relation/auxiliary_statement'
              Relation.include(Relation::AuxiliaryStatement)

              # Define the exposed constant for both types of auxiliary statements
              if config.exposed_class.present?
                *ns, name = config.exposed_class.split('::')
                base = ns.present? ? ::Object.const_get(ns.join('::')) : ::Object
                base.const_set(name, AuxiliaryStatement)

                *ns, name = config.exposed_recursive_class.split('::')
                base = ns.present? ? ::Object.const_get(ns.join('::')) : ::Object
                base.const_set(name, AuxiliaryStatement::Recursive)
              end
            end

            ## Enum Enabled Setup
            if (config = torque_config.enum).enabled
              require_relative 'adapter/oid/enum'
              require_relative 'adapter/oid/enum_set'

              require_relative 'attributes/enum'
              require_relative 'attributes/enum_set'

              Attributes::Enum.include_on(ActiveRecord::Base)
              Attributes::EnumSet.include_on(ActiveRecord::Base)

              ar_type.register(:enum,     Adapter::OID::Enum,    adapter: :postgresql)
              ar_type.register(:enum_set, Adapter::OID::EnumSet, adapter: :postgresql)

              if config.namespace == false
                # TODO: Allow enum classes to exist without a namespace
                config.namespace = PostgreSQL.const_set('Enum', Module.new)
              else
                config.namespace ||= ::Object.const_set('Enum', Module.new)

                # Define a method to find enumerators based on the namespace
                config.namespace.define_singleton_method(:const_missing) do |name|
                  Attributes::Enum.lookup(name)
                end

                # Define a helper method to get a sample value
                config.namespace.define_singleton_method(:sample) do |name|
                  Attributes::Enum.lookup(name).sample
                end
              end
            end

            ## Geometry Enabled Setup
            if (config = torque_config.geometry).enabled
              require_relative 'adapter/oid/box'
              require_relative 'adapter/oid/circle'
              require_relative 'adapter/oid/line'
              require_relative 'adapter/oid/segment'

              ar_type.register(:box,     Adapter::OID::Box,     adapter: :postgresql)
              ar_type.register(:circle,  Adapter::OID::Circle,  adapter: :postgresql)
              ar_type.register(:line,    Adapter::OID::Line,    adapter: :postgresql)
              ar_type.register(:segment, Adapter::OID::Segment, adapter: :postgresql)
            end

            ## Period Enabled Setup
            if (config = torque_config.period).enabled
              require_relative 'attributes/period'
              Attributes::Period.include_on(ActiveRecord::Base)
            end

            ## Interval Enabled Setup
            if (config = torque_config.interval).enabled
              require_relative 'adapter/oid/interval'
              ar_type.register(:interval, Adapter::OID::Interval, adapter: :postgresql)
            end

            ## Full Text Search Enabled Setup
            if (config = torque_config.full_text_search).enabled
              require_relative 'attributes/full_text_search'
              Attributes::FullTextSearch.include_on(ActiveRecord::Base)
            end

            ## Arel Setup
            PostgreSQL::Arel.build_operations(torque_config.arel.infix_operators)

            # Make sure to load all the types that are handled by this gem on
            # each individual PG connection
            adapter = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
            ActiveRecord::Base.connection_handler.each_connection_pool do |pool|
              next unless pool.db_config.adapter_class.is_a?(adapter)

              pool.with_connection { |conn| conn.torque_load_additional_types }
            end
          end
        end
      end
    end
  end
end
