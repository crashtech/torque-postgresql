# frozen_string_literal: true

module Torque
  module PostgreSQL
    module SchemaCache
      module Inheritance

        # Try to find a model based on a given table
        def lookup_model(table_name, scoped_class = '', source_to_model:)
          scoped_class = scoped_class.name if scoped_class.is_a?(Class)
          return source_to_model[table_name] if source_to_model.key?(table_name)

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
            return source_to_model[table_name] = model unless model.nil?
            scopes.pop
          end

          # If this part is reach, no model name was found
          raise LookupError.new(<<~MSG.squish)
            Unable to find a valid model that is associated with the
            '#{table_name}' table. Please, check if they correctly inherit from
            ActiveRecord::Base
          MSG
        end

        protected

          # Find a model by a given max namespaced class name that matches the
          # given table name
          def find_model(max_name, table_name, scope = Object)
            pieces = max_name.is_a?(::Array) ? max_name : max_name.split(/(::)/)
            ns_places = (1..(max_name.size - 1)).step(2).to_a

            # Generate all possible combinations
            conditions = []
            range = Torque::PostgreSQL.config.inheritance.inverse_lookup \
              ? 0.upto(ns_places.size) \
              : ns_places.size.downto(0)
            range.each do |size|
              conditions.concat(ns_places.combination(size).to_a)
            end

            # Now iterate over
            while (condition = conditions.shift)
              ns_places.each do |i|
                pieces[i] = condition.include?(i) ? '::' : ''
              end

              candidate = pieces.join
              candidate.prepend("#{scope.name}::") unless scope === Object

              klass = candidate.safe_constantize
              next if klass.nil?

              # Check if the class match the table name
              return klass if klass < ::ActiveRecord::Base &&
                klass.table_name == table_name
            end
          end

          # Calculates the inverted dependency (association), where even indirect
          # inheritance comes up in the list
          def generate_associations(inheritance_dependencies)
            return {} if inheritance_dependencies.empty?

            result = Hash.new{ |h, k| h[k] = [] }
            masters = inheritance_dependencies.values.flatten.uniq

            # Add direct associations
            masters.map do |master|
              inheritance_dependencies.each do |(dependent, associations)|
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

          # Parse the Torque config into the proper hash of irregular models.
          # This is smart enough to only load necessary models
          def prepare_irregular_models(data_sources)
            entries = Torque::PostgreSQL.config.irregular_models
            entries.slice(*data_sources).each_with_object({}) do |(table, model), hash|
              hash[table] = model.is_a?(Class) ? model : model.constantize
            end
          end

      end
    end
  end
end
