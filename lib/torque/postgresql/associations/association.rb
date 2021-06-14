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

        def skip_statement_cache?(*)
          super || reflection.connected_through_array?
        end

        private

          def set_owner_attributes(record)
            return super unless reflection.connected_through_array?

            add_id = owner[reflection.active_record_primary_key]
            record_fk = reflection.foreign_key

            record[record_fk].push(add_id) unless (record[record_fk] ||= []).include?(add_id)
          end

      end

      ::ActiveRecord::Associations::Association.prepend(Association)
    end
  end
end
