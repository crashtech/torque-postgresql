# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Associations
      module Preloader
        module Association

          delegate :connected_through_array?, to: :@reflection

          # For reflections connected through an array, make sure to properly
          # decuple the list of ids and set them as associated with the owner
          def run
            return super unless connected_through_array?
            send("run_array_for_#{@reflection.macro}")
          end

          private

            # Specific run for belongs_many association
            def run_array_for_belongs_to_many
              # Add reverse to has_many
              records = groupped_records
              owners.each do |owner|
                items = records.values_at(*Array.wrap(owner[owner_key_name]))
                associate_records_to_owner(owner, items.flatten)
              end
            end

            # Specific run for has_many association
            def run_array_for_has_many
              # Add reverse to belongs_to_many
              records = Hash.new { |h, k| h[k] = [] }
              groupped_records.each do |ids, record|
                ids.each { |id| records[id].concat(Array.wrap(record)) }
              end

              records.default_proc = nil
              owners.each do |owner|
                associate_records_to_owner(owner, records[owner[owner_key_name]] || [])
              end
            end

            if PostgreSQL::AR610
            # This is how Rails 6.1 now load the records
              def load_records
                return super unless connected_through_array?

                @records_by_owner = {}.compare_by_identity
                raw_records = owner_keys.empty? ? [] : records_for(owner_keys)

                @preloaded_records = raw_records.select do |record|
                  assignments = false

                  ids = convert_key(record[association_key_name])
                  owners_by_key.values_at(*ids).flat_map do |owner|
                    entries = (@records_by_owner[owner] ||= [])

                    if reflection.collection? || entries.empty?
                      entries << record
                      assignments = true
                    end
                  end

                  assignments
                end
              end
            end

            # Build correctly the constraint condition in order to get the
            # associated ids
            def records_for(ids, &block)
              return super unless connected_through_array?
              condition = scope.arel_table[association_key_name]
              condition = reflection.build_id_constraint(condition, ids.flatten.uniq)
              scope.where(condition).load(&block)
            end

            def associate_records_to_owner(owner, records)
              return super unless connected_through_array?
              association = owner.association(reflection.name)
              association.loaded!
              association.target.concat(records)
            end

            def groupped_records
              preloaded_records.group_by do |record|
                convert_key(record[association_key_name])
              end
            end
        end

        ::ActiveRecord::Associations::Preloader::Association.prepend(Association)
      end
    end
  end
end
