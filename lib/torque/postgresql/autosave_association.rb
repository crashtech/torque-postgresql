module Torque
  module PostgreSQL
    module AutosaveAssociation
      module ClassMethods
        def add_autosave_association_callbacks(reflection)
          return super unless reflection.macro.eql?(:belongs_to_many)

          save_method = :"autosave_associated_records_for_#{reflection.name}"
          define_non_cyclic_method(save_method) { save_belongs_to_many_array(reflection) }

          before_save(:before_save_collection_association)
          after_save(:after_save_collection_association) if ::ActiveRecord::Base
            .instance_methods.include?(:after_save_collection_association)

          before_create(save_method)
          before_update(save_method)

          define_autosave_validation_callbacks(reflection)
        end
      end

      def save_belongs_to_many_array(reflection)
        save_collection_association(reflection)

        association = association_instance_get(reflection.name)
        return unless association

        klass_fk = reflection.foreign_key
        acpk = reflection.active_record_primary_key

        records = association.target.each_with_object(klass_fk)
        write_attribute(acpk, records.map(&:read_attribute).compact)
      end
    end

    ::ActiveRecord::Base.singleton_class.prepend(AutosaveAssociation::ClassMethods)
    ::ActiveRecord::Base.include(AutosaveAssociation)
  end
end
