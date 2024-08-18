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

      def add(connection_or_table_name, table_name = connection_or_table_name, *) # :nodoc:
        super

        # Reset inheritance information when a table is added
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

      def clear_data_source_cache!(connection_or_name, name = connection_or_name) # :nodoc:
        Torque::PostgreSQL::AR710 ? super : super(name)
        @data_sources_model_names.delete name
        @inheritance_dependencies.delete name
        @inheritance_associations.delete name
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
      def add_model_name(*args)
        model, *source = args.reverse
        return unless data_source_exists?(*source.reverse) && model.is_a?(Class)

        @data_sources_model_names[source.first] = model
      end

      # Get all the tables that the given one inherits from
      def dependencies(source, table_name = source)
        reload_inheritance_data!(source == table_name ? connection : source)
        @inheritance_dependencies[table_name]
      end

      # Get the list of all tables that are associated (direct or indirect
      # inheritance) with the provided one
      def associations(source, table_name = source)
        reload_inheritance_data!(source == table_name ? connection : source)
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
        def reload_inheritance_data!(source)
          return if @inheritance_loaded

          method_name = Torque::PostgreSQL::AR720 ? :with_connection : :then
          source.public_send(method_name) do |connection|
            @inheritance_dependencies = connection.inherited_tables
            @inheritance_associations = generate_associations
            @inheritance_loaded = true
          end
        end

        # Calculates the inverted dependency (association), where even indirect
        # inheritance comes up in the list
        def generate_associations
          super(@inheritance_dependencies)
        end

        # Use this method to also load any irregular model name
        method_name = Torque::PostgreSQL::AR720 ? :add_all : :prepare_data_sources
        define_method(method_name) do |source = nil|
          Torque::PostgreSQL::AR710 ? super(source) : super()

          data_sources = source.present? ? tables_to_cache(source) : @data_sources.keys
          @data_sources_model_names = prepare_irregular_models(data_sources)
        end

    end

    ActiveRecord::ConnectionAdapters::SchemaCache.prepend SchemaCache
  end
end
