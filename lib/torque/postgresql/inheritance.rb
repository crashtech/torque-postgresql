module Torque
  module PostgreSQL
    module Inheritance
      extend ActiveSupport::Concern

      module ClassMethods

        def physically_inherited?
          @physically_inherited ||= connection.schema_cache.has_depencendy?(
            defined?(@table_name) ? @table_name : decorated_table_name,
          )
        end

        def inheritance_dependents
          connection.schema_cache.associations[table_name]
        end

        def physically_inheritances?
          inheritance_dependents.present?
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
    end

    ActiveRecord::Base.include Inheritance
  end
end
