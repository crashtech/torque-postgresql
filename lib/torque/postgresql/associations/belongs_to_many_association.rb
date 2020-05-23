require 'active_record/associations/collection_association'
# FIXME: build, create
module Torque
  module PostgreSQL
    module Associations
      class BelongsToManyAssociation < ::ActiveRecord::Associations::CollectionAssociation
        include ::ActiveRecord::Associations::ForeignAssociation

        def handle_dependency
          case options[:dependent]
          when :restrict_with_exception
            raise ::ActiveRecord::DeleteRestrictionError.new(reflection.name) unless empty?

          when :restrict_with_error
            unless empty?
              record = owner.class.human_attribute_name(reflection.name).downcase
              owner.errors.add(:base, :'restrict_dependent_destroy.has_many', record: record)
              throw(:abort)
            end

          when :destroy
            # No point in executing the counter update since we're going to destroy the parent anyway
            load_target.each { |t| t.destroyed_by_association = reflection }
            destroy_all
          else
            delete_all
          end
        end

        def ids_reader
          owner[reflection.active_record_primary_key]
        end

        def ids_writer(new_ids)
          column = reflection.active_record_primary_key
          command = owner.persisted? ? :update_column : :write_attribute
          owner.public_send(command, column, new_ids.presence)
          @association_scope = nil
        end

        def insert_record(record, *)
          super

          attribute = (ids_reader || owner[reflection.active_record_primary_key] = [])
          attribute.push(record[klass_fk])
          record
        end

        def empty?
          size.zero?
        end

        def include?(record)
          list = owner[reflection.active_record_primary_key]
          ids_reader && ids_reader.include?(record[klass_fk])
        end

        private

          # Returns the number of records in this collection, which basically
          # means count the number of entries in the +primary_key+
          def count_records
            ids_reader&.size || (@target ||= []).size
          end

          # When the idea is to nulligy the association, then just set the owner
          # +primary_key+ as empty
          def delete_count(method, scope, ids = nil)
            ids ||= scope.pluck(klass_fk)
            scope.delete_all if method == :delete_all
            remove_stash_records(ids)
          end

          def delete_or_nullify_all_records(method)
            delete_count(method, scope)
          end

          # Deletes the records according to the <tt>:dependent</tt> option.
          def delete_records(records, method)
            ids = Array.wrap(records).each_with_object(klass_fk).map(&:[])

            if method == :destroy
              records.each(&:destroy!)
              remove_stash_records(ids)
            else
              scope = self.scope.where(klass_fk => records)
              delete_count(method, scope, ids)
            end
          end

          def concat_records(*)
            result = super
            ids_writer(ids_reader)
            result
          end

          def remove_stash_records(ids)
            return if ids_reader.nil?
            ids_writer(ids_reader - Array.wrap(ids))
          end

          def klass_fk
            reflection.foreign_key
          end

          def difference(a, b)
            a - b
          end

          def intersection(a, b)
            a & b
          end
      end

      ::ActiveRecord::Associations.const_set(:BelongsToManyAssociation, BelongsToManyAssociation)
    end
  end
end
