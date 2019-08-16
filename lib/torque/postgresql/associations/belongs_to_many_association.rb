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

        def insert_record(record, validate = true, raise_error = false, &block)
          owner[reflection.active_record_primary_key] ||= []
          owner[reflection.active_record_primary_key].push(record)

          call_method = raise_error ? :save! : :save
          owner.public_send(call_method, validate: validate, &block)

          super unless record.persisted?
        end

        def empty?
          size.zero?
        end

        private

          # Returns the number of records in this collection, which basically
          # means count the number of entries in the +primary_key+
          def count_records
            owner[reflection.active_record_primary_key]&.size || (@target ||= []).size
          end

          # When the idea is to nulligy the association, then just set the owner
          # +primary_key+ as empty
          def delete_count(method, scope)
            new_value = owner[reflection.active_record_primary_key]
            new_value -= Array(scope.where_values_hash[reflection.klass.primary_key])

            scope.delete_all if method == :delete_all

            # TODO: Stash the owner change and perform it at the end
            owner.update(reflection.active_record_primary_key => new_value.presence)
          end

          def delete_or_nullify_all_records(method)
            delete_count(method, scope)
          end

          # Deletes the records according to the <tt>:dependent</tt> option.
          def delete_records(records, method)
            if method == :destroy
              keys = records.each_with_object(reflection.klass.primary_key)

              new_value = owner[reflection.active_record_primary_key]
              new_value -= Array(keys.map(&:_read_attribute))

              # TODO: Stash the owner change and perform it at the end
              owner.update(reflection.active_record_primary_key => new_value)
              records.each(&:destroy!)
            else
              scope = self.scope.where(reflection.klass.primary_key => records)
              delete_count(method, scope)
            end
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
