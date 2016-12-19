module Torque
  module PostgreSQL
    module Relation
      module DistinctOn

        attr_accessor :distinct_on_value

        # Specifies whether the records should be unique or not by a given set of fields.
        # For example:
        #
        #   User.distinct_on(:name)
        #   # Returns 1 record per distinct name
        #
        #   User.distinct_on(:name, :email)
        #   # Returns 1 record per distinct name and email
        #
        #   User.distinct_on(false)
        #   # You can also remove the uniqueness
        def distinct_on(*value)
          spawn.distinct_on!(*value)
        end

        # Like #distinct_on, but modifies relation in place.
        def distinct_on!(*value)
          self.distinct_on_value = value
          self
        end

        private

          # Hook arel build to add the distinct on clause
          def build_arel
            arel = super

            value = self.distinct_on_value
            arel.distinct_on(resolve_column(value)) unless value.nil?
            arel
          end

      end
    end
  end
end
