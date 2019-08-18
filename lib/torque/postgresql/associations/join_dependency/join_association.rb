module Torque
  module PostgreSQL
    module Associations
      module JoinDependency
        module JoinAssociation
          def build_constraint(_, table, _, foreign_table, _)
            reflection.build_join_constraint(table, foreign_table)
          end
        end

        ::ActiveRecord::Associations::JoinDependency::JoinAssociation.prepend(JoinAssociation)
      end
    end
  end
end
