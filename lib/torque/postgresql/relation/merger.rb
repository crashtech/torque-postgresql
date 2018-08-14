module Torque
  module PostgreSQL
    module Relation
      module Merger

        def merge
          super

          merge_distinct_on
          merge_auxiliary_statements
          merge_inheritance

          relation
        end

        private

          def merge_distinct_on
            return if other.distinct_on_values.blank?
            relation.distinct_on_values += other.distinct_on_values
          end

          def merge_auxiliary_statements
            return if other.auxiliary_statements_values.blank?

            current = relation.auxiliary_statements_values.map{ |cte| cte.class }
            other.auxiliary_statements_values.each do |other|
              next if current.include?(other.class)
              relation.auxiliary_statements_values += [other]
              current << other.class
            end
          end

          def merge_inheritance
            relation.cast_records_value = true if other.cast_records_value
            relation.from_only_value = true if other.from_only_value
          end

      end

      ActiveRecord::Relation::Merger.prepend Merger
    end
  end
end
