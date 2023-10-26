# frozen_string_literal: true

module Torque
  module PostgreSQL
    LookupError = Class.new(ArgumentError)

    # :TODO: Create the +add+ to load inheritance info
    module SchemaCache

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

      def add(table_name, *) # :nodoc:
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

      def clear_data_source_cache!(name, *) # :nodoc:
        super
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
      def add_model_name(table_name, model)
        return unless data_source_exists?(table_name) && model.is_a?(Class)
        @data_sources_model_names[table_name] = model
      end

      # Get all the tables that the given one inherits from
      def dependencies(table_name)
        reload_inheritance_data!
        @inheritance_dependencies[table_name]
      end

      # Get the list of all tables that are associated (direct or indirect
      # inheritance) with the provided one
      def associations(table_name)
        reload_inheritance_data!
        @inheritance_associations[table_name]
      end

      # Try to find a model based on a given table
      def lookup_model(table_name, scoped_class = '')
        scoped_class = scoped_class.name if scoped_class.is_a?(Class)
        return @data_sources_model_names[table_name] \
          if @data_sources_model_names.key?(table_name)

        # Get all the possible scopes
        scopes = scoped_class.scan(/(?:::)?[A-Z][a-z]+/)
        scopes.unshift('Object::')

        # Check if the table name comes with a schema
        if table_name.include?('.')
          schema, table_name = table_name.split('.')
          scopes.insert(1, schema.camelize) if schema != 'public'
        end

        # Consider the maximum namespaced possible model name
        max_name = table_name.tr('_', '/').camelize.split(/(::)/)
        max_name[-1] = max_name[-1].singularize

        # Test all the possible names against all the possible scopes
        until scopes.size == 0
          scope = scopes.join.chomp('::').safe_constantize
          model = find_model(max_name, table_name, scope) unless scope.nil?
          return @data_sources_model_names[table_name] = model unless model.nil?
          scopes.pop
        end

        # If this part is reach, no model name was found
        raise LookupError.new(<<~MSG.squish)
          Unable to find a valid model that is associated with the '#{table_name}' table.
          Please, check if they correctly inherit from ActiveRecord::Base
        MSG
      end

      private

        # Find a model by a given max namespaced class name thath matches the
        # given table name
        def find_model(max_name, table_name, scope = Object)
          pieces = max_name.is_a?(::Array) ? max_name : max_name.split(/(::)/)
          ns_places = (1..(max_name.size - 1)).step(2).to_a

          # Generate all possible combinarions
          conditions = []
          range = Torque::PostgreSQL.config.inheritance.inverse_lookup \
            ? 0.upto(ns_places.size) \
            : ns_places.size.downto(0)
          range.each do |size|
            conditions.concat(ns_places.combination(size).to_a)
          end

          # Now iterate over
          while (condition = conditions.shift)
            ns_places.each{ |i| pieces[i] = condition.include?(i) ? '::' : '' }

            candidate = pieces.join
            candidate.prepend("#{scope.name}::") unless scope === Object

            klass = candidate.safe_constantize
            next if klass.nil?

            # Check if the class match the table name
            return klass if klass < ::ActiveRecord::Base && klass.table_name == table_name
          end
        end

        # Reload information about tables inheritance and dependencies, uses a
        # cache to not perform additional checkes
        def reload_inheritance_data!
          return if @inheritance_loaded
          @inheritance_dependencies = connection.inherited_tables
          @inheritance_associations = generate_associations
          @inheritance_loaded = true
        end

        # Calculates the inverted dependency (association), where even indirect
        # inheritance comes up in the list
        def generate_associations
          return {} if @inheritance_dependencies.empty?

          result = Hash.new{ |h, k| h[k] = [] }
          masters = @inheritance_dependencies.values.flatten.uniq

          # Add direct associations
          masters.map do |master|
            @inheritance_dependencies.each do |(dependent, associations)|
              result[master] << dependent if associations.include?(master)
            end
          end

          # Add indirect associations
          result.each do |master, children|
            children.each do |child|
              children.concat(result[child]).uniq! if result.key?(child)
            end
          end

          # Remove the default proc that would create new entries
          result.default_proc = nil
          result
        end

        # Use this method to also load any irregular model name. This is smart
        # enought to only load the sources present on this instance
        def prepare_data_sources(...)
          super(...)
          @data_sources_model_names = Torque::PostgreSQL.config
            .irregular_models.slice(*@data_sources.keys).map do |table_name, model_name|
            [table_name, (model_name.is_a?(Class) ? model_name : model_name.constantize)]
          end.to_h
        end

    end

    module BoundSchemaReflection
      def initialize(*) # :nodoc:
        super

        @data_sources_model_names = {}
        @inheritance_dependencies = {}
        @inheritance_associations = {}
        @inheritance_loaded = false
      end

      # Get all the tables that the given one inherits from
      def dependencies(table_name)
        reload_inheritance_data!
        @inheritance_dependencies[table_name]
      end

      # Get the list of all tables that are associated (direct or indirect
      # inheritance) with the provided one
      def associations(table_name)
        reload_inheritance_data!
        @inheritance_associations[table_name]
      end

      # private

        # Reload information about tables inheritance and dependencies, uses a
        # cache to not perform additional checkes
        def reload_inheritance_data!
          return if @inheritance_loaded
          @inheritance_dependencies = @connection.inherited_tables
          @inheritance_associations = generate_associations
          @inheritance_loaded = true
        end

        # Calculates the inverted dependency (association), where even indirect
        # inheritance comes up in the list
        def generate_associations
          return {} if @inheritance_dependencies.empty?

          result = Hash.new{ |h, k| h[k] = [] }
          masters = @inheritance_dependencies.values.flatten.uniq

          # Add direct associations
          masters.map do |master|
            @inheritance_dependencies.each do |(dependent, associations)|
              result[master] << dependent if associations.include?(master)
            end
          end

          # Add indirect associations
          result.each do |master, children|
            children.each do |child|
              children.concat(result[child]).uniq! if result.key?(child)
            end
          end

          # Remove the default proc that would create new entries
          result.default_proc = nil
          result
        end

        def cache
          @schema_reflection.send(:cache, @connection)
        end

        # Use this method to also load any irregular model name. This is smart
        # enought to only load the sources present on this instance
        def prepare_data_sources(*)
          cache.send(:prepare_data_sources, @connection)
        end

        # Try to find a model based on a given table
        def lookup_model(table_name, scoped_class = '')
          cache.send :lookup_model, table_name, scoped_class
        end
    end

    ActiveRecord::ConnectionAdapters::SchemaCache.prepend SchemaCache

    if Object.const_defined?("ActiveRecord::ConnectionAdapters::BoundSchemaReflection")
      ActiveRecord::ConnectionAdapters::BoundSchemaReflection.prepend BoundSchemaReflection
    end
  end
end
