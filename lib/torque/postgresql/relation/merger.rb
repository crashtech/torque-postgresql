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
            return unless defined?(Relation::AuxiliaryStatement) && relation.is_a?(Relation::AuxiliaryStatement)
            return if other.auxiliary_statements_values.blank?

            current = relation.auxiliary_statements_values.map{ |cte| cte.class }
            other.auxiliary_statements_values.each do |other|
              next if current.include?(other.class)
              relation.auxiliary_statements_values += [other]
              current << other.class
            end
          end

          # Merge settings related to inheritance tables, going through the
          # public operations so that their conflicts are still detected
          def merge_inheritance
            return unless relation.is_a?(Relation::Inheritance)

            relation.itself_only! if other.itself_only_value.present?

            return if other.expand_records_values.blank?

            if relation.model == other.model
              types = (relation.expand_records_values + other.expand_records_values).uniq
              relation.expand_records!(*types, eager_load: other.expand_records_eager_load_value)
            else
              raise_eager_load_conflict! if other.expand_records_eager_load_value

              relation.expand_records_scoped_value = relation.expand_records_scoped_value
                .merge(other.model => other.expand_records_values) { |_, a, b| (a + b).uniq }
            end
          end

          def raise_eager_load_conflict!
            raise InheritanceError.new(<<~MSG.squish)
              Expanding the records of a different model happens through a
              preload, which has no query to eager load the inherited tables
              into, so the two cannot be merged.
            MSG
          end

          # Merge settings related to buckets
          def merge_buckets
            return unless defined?(Relation::Buckets) && relation.is_a?(Relation::Buckets)
            return if other.buckets_value.blank?

            relation.buckets_value = other.buckets_value
          end

      end

      ActiveRecord::Relation::Merger.prepend Merger
    end
  end
end
