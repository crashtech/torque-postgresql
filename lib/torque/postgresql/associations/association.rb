# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Associations
      module Association

        def inversed_from(record)
          return super unless reflection.connected_through_array?

          self.target ||= []
          self.target.push(record) unless self.target.include?(record)
          @inversed = self.target.present?
        end

        private

          def set_owner_attributes(record)
            return super unless reflection.connected_through_array?

            add_id = owner[reflection.active_record_primary_key]
            record_fk = reflection.foreign_key

            list = record[record_fk] ||= []
            list.push(add_id) unless list.include?(add_id)
          end

      end

      ::ActiveRecord::Associations::Association.prepend(Association)
      ::ActiveRecord::Associations::HasManyAssociation.prepend(Association)
    end
  end
end
