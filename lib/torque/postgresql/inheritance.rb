module Torque
  module PostgreSQL
    module Inheritance
      extend ActiveSupport::Concern

      module ClassMethods

        def physically_inherited?
          @physically_inherited ||= Inheritance.has_depencendy?(
            defined?(@table_name) ? @table_name : decorated_table_name,
          )
        end

        private

          def decorated_table_name
            if parent < Base && !parent.abstract_class?
              contained = parent.table_name
              contained = contained.singularize if parent.pluralize_table_names
              contained += "_"
            end

            "#{full_table_name_prefix}#{contained}#{undecorated_table_name(name)}#{full_table_name_suffix}"
          end

          def compute_table_name
            return super unless physically_inherited?
            decorated_table_name
          end

      end

      # TODO: Migrate this operations under the connection
      class << self

        def associations
          @associations ||= begin
            reload!
            @associations
          end
        end

        def dependencies
          @dependencies ||= begin
            reload!
            @dependencies
          end
        end

        def has_depencendy?(table_name)
          dependencies.key?(table_name) || begin
            reload!
            dependencies.key?(table_name)
          end
        end

        private

          def connection
            ActiveRecord::Base.connection
          end

          def data_sources_size
            connection.schema_cache.instance_variable_get(:@data_sources).size
          end

          def reload!
            return unless @sources_loaded != data_sources_size
            @sources_loaded = data_sources_size
            @dependencies = connection.inherited_tables
            @associations = generate_associations
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
    end

    ActiveRecord::Base.include Inheritance
  end
end
