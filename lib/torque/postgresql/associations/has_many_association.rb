module Torque
  module PostgreSQL
    module Associations
      module HasManyAssociation
      end

      ::ActiveRecord::Associations::HasManyAssociation.prepend(HasManyAssociation)
    end
  end
end
