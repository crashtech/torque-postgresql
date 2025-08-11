# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Relation
      module Merger

        def merge # :nodoc:
          super

          merge_select_extra
          merge_distinct_on
          merge_auxiliary_statements
          merge_inheritance
          merge_buckets

          relation
        end

        private

          # Merge extra select columns
          def merge_select_extra
            relation.select_extra_values.concat(other.select_extra_values).uniq! \
              if other.select_extra_values.present?
          end

          # Merge distinct on columns
          def merge_distinct_on
            return unless relation.is_a?(Relation::DistinctOn)
            return if other.distinct_on_values.blank?

            relation.distinct_on_values += other.distinct_on_values
          end

          # Merge auxiliary statements activated by +with+
          def merge_auxiliary_statements
            return unless relation.is_a?(Relation::AuxiliaryStatement)
            return if other.auxiliary_statements_values.blank?

            current = relation.auxiliary_statements_values.map{ |cte| cte.class }
            other.auxiliary_statements_values.each do |other|
              next if current.include?(other.class)
              relation.auxiliary_statements_values += [other]
              current << other.class
            end
          end

          # Merge settings related to inheritance tables
          def merge_inheritance
            return unless relation.is_a?(Relation::Inheritance)

            relation.itself_only_value = true if other.itself_only_value.present?

            if other.cast_records_values.present?
              relation.cast_records_values += other.cast_records_values
              relation.cast_records_values.uniq!
            end
          end

          # Merge settings related to buckets
          def merge_buckets
            return unless relation.is_a?(Relation::Buckets)
            return if other.buckets_value.blank?

            relation.buckets_value = other.buckets_value
          end

      end

      ActiveRecord::Relation::Merger.prepend Merger
    end
  end
end
