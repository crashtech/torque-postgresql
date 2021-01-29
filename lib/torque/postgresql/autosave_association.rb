# frozen_string_literal: true

module Torque
  module PostgreSQL
    module AutosaveAssociation
      module ClassMethods
        # Since belongs to many is a collection, the callback would normally go
        # to +after_create+. However, since it is a +belongs_to+ kind of
        # association, it neds to be executed +before_save+
        def add_autosave_association_callbacks(reflection)
          return super unless reflection.macro.eql?(:belongs_to_many)

          save_method = :"autosave_associated_records_for_#{reflection.name}"
          define_non_cyclic_method(save_method) do
            save_belongs_to_many_association(reflection)
          rescue ::ActiveRecord::RecordInvalid
            throw(:abort)
          end

          around_save(:around_save_collection_association)
          before_save(save_method)

          define_autosave_validation_callbacks(reflection)
        end
      end

      # Build all the changes before actually changing the owner record for a
      # simpler one-time update
      def save_belongs_to_many_association(reflection)
        association = association_instance_get(reflection.name)
        association&.build_changes { save_collection_association(reflection) }
      end

      unless PostgreSQL::AR610
        def around_save_collection_association
          previously_new_record_before_save = (@new_record_before_save ||= false)
          @new_record_before_save = !previously_new_record_before_save && new_record?

          yield
        ensure
          @new_record_before_save = previously_new_record_before_save
        end
      end
    end

    ::ActiveRecord::Base.singleton_class.prepend(AutosaveAssociation::ClassMethods)
    ::ActiveRecord::Base.include(AutosaveAssociation)
  end
end
