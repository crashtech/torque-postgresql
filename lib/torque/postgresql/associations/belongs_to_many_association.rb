# frozen_string_literal: true

require 'active_record/associations/collection_association'

# FIXME: build, create
module Torque
  module PostgreSQL
    module Associations
      class BelongsToManyAssociation < ::ActiveRecord::Associations::CollectionAssociation
        include ::ActiveRecord::Associations::ForeignAssociation

        ## CUSTOM
        def ids_reader
          if loaded?
            target.pluck(reflection.association_primary_key)
          elsif !target.empty?
            load_target.pluck(reflection.association_primary_key)
          else
            stale_state || column_default_value
          end
        end

        def ids_writer(ids)
          ids = ids.presence || column_default_value
          owner.write_attribute(source_attr, ids)
          return unless owner.persisted? && owner.attribute_changed?(source_attr)

          owner.update_attribute(source_attr, ids)
        end

        def size
          if loaded?
            target.size
          elsif !target.empty?
            unsaved_records = target.select(&:new_record?)
            unsaved_records.size + stale_state.size
          else
            stale_state&.size || 0
          end
        end

        def empty?
          size.zero?
        end

        def include?(record)
          return false unless record.is_a?(reflection.klass)
          return include_in_memory?(record) if record.new_record?

          (!target.empty? && target.include?(record)) ||
            stale_state&.include?(record.read_attribute(klass_attr))
        end

        def load_target
          if stale_target? || find_target?
            persisted_records = (find_target || []) + target.extract!(&:persisted?)
            @target = merge_target_lists(persisted_records, target)
          end

          loaded!
          target
        end

        def build_changes(from_target = false)
          return yield if defined?(@_building_changes) && @_building_changes

          @_building_changes = true
          yield.tap { ids_writer(from_target ? ids_reader : stale_state) }
        ensure
          @_building_changes = nil
        end

        ## HAS MANY
        def handle_dependency
          case options[:dependent]
          when :restrict_with_exception
            raise ActiveRecord::DeleteRestrictionError.new(reflection.name) unless empty?

          when :restrict_with_error
            unless empty?
              record = owner.class.human_attribute_name(reflection.name).downcase
              owner.errors.add(:base, :'restrict_dependent_destroy.has_many', record: record)
              throw(:abort)
            end

          when :destroy
            load_target.each { |t| t.destroyed_by_association = reflection }
            destroy_all
          when :destroy_async
            load_target.each do |t|
              t.destroyed_by_association = reflection
            end

            unless target.empty?
              association_class = target.first.class
              primary_key_column = association_class.primary_key.to_sym

              ids = target.collect do |assoc|
                assoc.public_send(primary_key_column)
              end

              enqueue_destroy_association(
                owner_model_name: owner.class.to_s,
                owner_id: owner.id,
                association_class: association_class.to_s,
                association_ids: ids,
                association_primary_key_column: primary_key_column,
                ensuring_owner_was_method: options.fetch(:ensuring_owner_was, nil)
              )
            end
          else
            delete_all
          end
        end

        def insert_record(record, *)
          (record.persisted? || super).tap do |saved|
            ids_rewriter(record.read_attribute(klass_attr), :<<) if saved
          end
        end

        ## BELONGS TO
        def default(&block)
          writer(owner.instance_exec(&block)) if reader.nil?
        end

        private

          ## CUSTOM
          def _create_record(attributes, raises = false, &block)
            if attributes.is_a?(Array)
              attributes.collect { |attr| _create_record(attr, raises, &block) }
            else
              build_record(attributes, &block).tap do |record|
                transaction do
                  result = nil
                  add_to_target(record) do
                    result = insert_record(record, true, raises) { @_was_loaded = loaded? }
                  end
                  raise ActiveRecord::Rollback unless result
                end
              end
            end
          end

          # When the idea is to nullify the association, then just set the owner
          # +primary_key+ as empty
          def delete_count(method, scope, ids)
            size_cache = scope.delete_all if method == :delete_all
            (size_cache || ids.size).tap { ids_rewriter(ids, :-) }
          end

          def delete_or_nullify_all_records(method)
            delete_count(method, scope, ids_reader)
          end

          # Deletes the records according to the <tt>:dependent</tt> option.
          def delete_records(records, method)
            ids = read_records_ids(records)

            if method == :destroy
              records.each(&:destroy!)
              ids_rewriter(ids, :-)
            else
              scope = self.scope.where(klass_attr => records)
              delete_count(method, scope, ids)
            end
          end

          def source_attr
            reflection.foreign_key
          end

          def klass_attr
            reflection.active_record_primary_key
          end

          def read_records_ids(records)
            return unless records.present?
            Array.wrap(records).each_with_object(klass_attr).map(&:read_attribute).presence
          end

          def ids_rewriter(ids, operator)
            list = owner[source_attr] ||= []
            list = list.public_send(operator, ids)
            owner[source_attr] = list.uniq.compact.presence || column_default_value

            return if @_building_changes || !owner.persisted?
            owner.update_attribute(source_attr, list)
          end

          def column_default_value
            owner.class.columns_hash[source_attr].default
          end

          ## HAS MANY
          def replace_records(*)
            build_changes(true) { super }
          end

          def concat_records(*)
            build_changes(true) { super }
          end

          def delete_or_destroy(*)
            build_changes(true) { super }
          end

          def difference(a, b)
            a - b
          end

          def intersection(a, b)
            a & b
          end

          ## BELONGS TO
          def scope_for_create
            super.except!(klass.primary_key)
          end

          def find_target?
            !loaded? && foreign_key_present? && klass
          end

          def foreign_key_present?
            stale_state.present?
          end

          def invertible_for?(record)
            return unless (inverse = inverse_reflection_for(record))
            collection_class = ::ActiveRecord::Associations::HasManyAssociation
            inverse.is_a?(collection_class) && inverse.connected_through_array?
          end

          def stale_state
            owner.read_attribute(source_attr)
          end
      end

      ::ActiveRecord::Associations.const_set(:BelongsToManyAssociation, BelongsToManyAssociation)
    end
  end
end
