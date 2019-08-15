module Torque
  module PostgreSQL
    module Associations
      module Preloader
        module Association

          delegate :connected_through_array?, to: :@reflection

          # For reflections connected through an array, make sure to properly
          # decuple the list of ids and set them as associated with the owner
          def run(preloader)
            return super unless connected_through_array?

            simple_records = load_records
            # Add reverse of belongs_to_many
            # do |record|
            #   ids = convert_key(record[association_key_name])
            #   owners = owners_by_key.slice(*ids)

            #   association = owner.association(reflection.name)
            #   association.set_inverse_instance(record)
            # end

            records = Hash.new { |h, k| h[k] = [] }
            simple_records.each do |ids, record|
              ids.each { |id| records[id].concat(Array.wrap(record)) }
            end

            owners.each do |owner|
              associate_records_to_owner(owner, records[owner[owner_key_name]] || [])
            end
          end

          private

            # Build correctly the constraint condition in order to get the
            # associated ids
            def records_for(ids, &block)
              return super unless connected_through_array?
              condition = scope.arel_attribute(association_key_name)
              condition = reflection.build_id_constraint(condition, ids)
              scope.where(condition).load(&block)
            end

        end

        ::ActiveRecord::Associations::Preloader::Association.prepend(Association)
      end
    end
  end
end
