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

      end

      ::ActiveRecord::Associations::Association.prepend(Association)
    end
  end
end
