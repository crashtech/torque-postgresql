# frozen_string_literal: true

require 'torque/postgresql/schema_cache/inheritance'

if Torque::PostgreSQL::AR710
  require 'torque/postgresql/schema_cache/schema_reflection'
  require 'torque/postgresql/schema_cache/bound_schema_reflection'
end

module Torque
  module PostgreSQL
    LookupError = Class.new(ArgumentError)

    # :TODO: Create the +add+ to load inheritance info
    module SchemaCache
      include Torque::PostgreSQL::SchemaCache::Inheritance

      def initialize(*) # :nodoc:
        super

        @data_sources_model_names = {}
        @inheritance_dependencies = {}
        @inheritance_associations = {}
        @inheritance_loaded = false
      end

      def initialize_dup(*) # :nodoc:
        super
        @data_sources_model_names = @data_sources_model_names.dup
        @inheritance_dependencies = @inheritance_dependencies.dup
        @inheritance_associations = @inheritance_associations.dup
      end

      def encode_with(coder) # :nodoc:
        super
        coder['data_sources_model_names'] = @data_sources_model_names
        coder['inheritance_dependencies'] = @inheritance_dependencies
        coder['inheritance_associations'] = @inheritance_associations
      end

      def init_with(coder) # :nodoc:
        super
        @data_sources_model_names = coder['data_sources_model_names']
        @inheritance_dependencies = coder['inheritance_dependencies']
        @inheritance_associations = coder['inheritance_associations']
      end

      def add(*args) # :nodoc:
        super

        # Reset inheritance information when a table is added
        table_name = Torque::PostgreSQL::AR710 ? args[1] : args[0]
        if @data_sources.key?(table_name)
          @inheritance_dependencies.clear
          @inheritance_associations.clear
          @inheritance_loaded = false
        end
      end

      def clear! # :nodoc:
        super
        @data_sources_model_names.clear
        @inheritance_dependencies.clear
        @inheritance_associations.clear
        @inheritance_loaded = false
      end

      def size # :nodoc:
        super + [
          @data_sources_model_names,
          @inheritance_dependencies,
          @inheritance_associations,
        ].map(&:size).inject(:+)
      end

      def clear_data_source_cache!(connection_or_name, name = nil) # :nodoc:
        Torque::PostgreSQL::AR710 ? super : super(connection_or_name)
        @data_sources_model_names.delete name || connection_or_name
        @inheritance_dependencies.delete name || connection_or_name
        @inheritance_associations.delete name || connection_or_name
      end

      def marshal_dump # :nodoc:
        super + [
          @inheritance_dependencies,
          @inheritance_associations,
          @data_sources_model_names,
          @inheritance_loaded,
        ]
      end

      def marshal_load(array) # :nodoc:
        @inheritance_loaded = array.pop
        @data_sources_model_names = array.pop
        @inheritance_associations = array.pop
        @inheritance_dependencies = array.pop
        super
      end

      # A way to manually add models name so it doesn't need the lookup method
      def add_model_name(table_name, model)
        return unless data_source_exists?(table_name) && model.is_a?(Class)
        @data_sources_model_names[table_name] = model
      end

      # Get all the tables that the given one inherits from
      def dependencies(conn, table_name = nil)
        conn, table_name = connection, conn if table_name.nil?
        reload_inheritance_data!(conn)
        @inheritance_dependencies[table_name]
      end

      # Get the list of all tables that are associated (direct or indirect
      # inheritance) with the provided one
      def associations(conn, table_name = nil)
        conn, table_name = connection, conn if table_name.nil?
        reload_inheritance_data!(conn)
        @inheritance_associations[table_name]
      end

      # Override the inheritance implementation to pass over the proper cache of
      # the existing association between data sources and model names
      def lookup_model(*args, **xargs)
        super(*args, **xargs, source_to_model: @data_sources_model_names)
      end

      private

        # Reload information about tables inheritance and dependencies, uses a
        # cache to not perform additional checks
        def reload_inheritance_data!(connection)
          return if @inheritance_loaded
          @inheritance_dependencies = connection.inherited_tables
          @inheritance_associations = generate_associations
          @inheritance_loaded = true
        end

        # Calculates the inverted dependency (association), where even indirect
        # inheritance comes up in the list
        def generate_associations
          super(@inheritance_dependencies)
        end

        # Use this method to also load any irregular model name
        def prepare_data_sources(connection = nil)
          Torque::PostgreSQL::AR710 ? super : super()

          sources = connection.present? ? tables_to_cache(connection) : @data_sources.keys
          @data_sources_model_names = prepare_irregular_models(sources)
        end

    end

    ActiveRecord::ConnectionAdapters::SchemaCache.prepend SchemaCache
  end
end
