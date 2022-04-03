# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Associations
      module ForeignAssociation

        # There is no problem of adding temporary items on target because
        # CollectionProxy will handle memory and persisted relationship
        def inversed_from(record)
          return super unless reflection.connected_through_array?

          self.target ||= []
          self.target.push(record) unless self.target.include?(record)
          @inversed = self.target.present?
        end

        # The binds and the cache are getting mixed and caching the wrong query
        def skip_statement_cache?(*)
          super || reflection.connected_through_array?
        end

        private

          # This is mainly for the has many when connect through an array to add
          # its id to the list of the inverse belongs to many association
          def set_owner_attributes(record)
            return super unless reflection.connected_through_array?

            add_id = owner[reflection.active_record_primary_key]
            list = record[reflection.foreign_key] ||= []
            list.push(add_id) unless list.include?(add_id)
          end

      end
    end
  end
end
