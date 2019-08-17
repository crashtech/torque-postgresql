module Torque
  module PostgreSQL
    module AutosaveAssociation
      module ClassMethods
        def add_autosave_association_callbacks(reflection)
          return super unless reflection.connected_through_array?

          save_method = :"autosave_associated_records_for_#{reflection.name}"
          define_non_cyclic_method(save_method) do
            send("save_#{reflection.macro}_array", reflection)
          end

          before_save(:before_save_collection_association)
          after_save(:after_save_collection_association)

          if reflection.macro.eql?(:belongs_to_many)
            before_create(save_method)
            before_update(save_method)
          elsif reflection.macro.eql?(:has_many)
            after_create(save_method)
            after_update(save_method)
          end

          define_autosave_validation_callbacks(reflection)
        end
      end

      def save_belongs_to_many_array(reflection)
        save_collection_association(reflection)

        association = association_instance_get(reflection.name)
        return unless association

        klass_fk = reflection.foreign_key
        ac_pk = reflection.active_record_primary_key

        records = association.target.each_with_object(klass_fk)
        _write_attribute(ac_pk, records.map(&:_read_attribute).compact)
      end

      def save_has_many_array(reflection)
        association = association_instance_get(reflection.name)
        return unless association

        add_id = _read_attribute(reflection.foreign_key)
        ac_pk = reflection.active_record_primary_key
        association.target.each do |record|
          record[ac_pk].push(add_id) unless (record[ac_pk] ||= []).include?(add_id)
        end

        save_collection_association(reflection)
      end
    end

    ::ActiveRecord::Base.singleton_class.prepend(AutosaveAssociation::ClassMethods)
    ::ActiveRecord::Base.include(AutosaveAssociation)
  end
end
