module Torque
  module PostgreSQL
    module SchemaCache

      def associations
        @inheritance_associations ||= begin
          reload!
          @inheritance_associations
        end
      end

      def dependencies
        @inheritance_dependencies ||= begin
          reload!
          @inheritance_dependencies
        end
      end

      def has_depencendy?(table_name)
        dependencies.key?(table_name) || begin
          reload!
          dependencies.key?(table_name)
        end
      end

      private

        def data_sources_size
          connection.schema_cache.instance_variable_get(:@data_sources).size
        end

        def reload!
          return unless @cached_data_sources_size != data_sources_size
          @cached_data_sources_size = data_sources_size
          @inheritance_dependencies = connection.inherited_tables
          @inheritance_associations = generate_associations
        end

        def generate_associations
          result = Hash.new{ |h, k| h[k] = [] }
          masters = dependencies.values.flatten.uniq

          # Add direct associations
          masters.map do |master|
            dependencies.each do |(dependent, associations)|
              result[master] << dependent if associations.include?(master)
            end
          end

          # Add indirect associations
          result.each do |master, children|
            children.each do |child|
              children.concat(result[child]).uniq! if result.key?(child)
            end
          end

          result
        end

    end

    ActiveRecord::ConnectionAdapters::SchemaCache.prepend SchemaCache
  end
end
