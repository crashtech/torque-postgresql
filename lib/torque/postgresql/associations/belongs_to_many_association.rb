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
          def delete_count(method, scope)
            remove_stash_records(scope.where_values_hash[klass_fk])
            scope.delete_all if method == :delete_all
          end

          def delete_or_nullify_all_records(method)
            delete_count(method, scope)
          end

          # Deletes the records according to the <tt>:dependent</tt> option.
          def delete_records(records, method)
            if method == :destroy
              remove_stash_records(records_or_ids)
              records.each(&:destroy!)
            else
              scope = self.scope.where(klass_fk => records)
              delete_count(method, scope)
            end
          end

          def remove_stash_records(records_or_ids)
            records_or_ids.map! do |item|
              item.is_a?(::ActiveRecord::Base) ? item[klass_fk] : item.to_i
            end

            Array.wrap(records_or_ids).each(&ids_reader.method(:delete))
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
