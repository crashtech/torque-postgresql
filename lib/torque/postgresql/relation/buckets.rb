# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Relation
      module Buckets

        # :nodoc:
        def buckets_value
          @values.fetch(:buckets, nil)
        end
        # :nodoc:
        def buckets_value=(value)
          assert_modifiable!
          @values[:buckets] = value
        end

        # Specifies how to bucket records. It works for both the calculations
        # or just putting records into groups. For example:
        #
        #   User.buckets(:created_at, [1.year.ago, 1.month.ago, 1.week.ago])
        #   # Returns all users grouped by created_at in the given time ranges
        #
        #   User.buckets(:age, 0..100, step: 10).count
        #   # Counts all users grouped by age buckets of 10 years
        def buckets(*value, **xargs)
          spawn.buckets!(*value, **xargs)
        end

        # Like #buckets, but modifies relation in place.
        def buckets!(attribute, values, size: nil, cast: nil, as: nil)
          raise ArgumentError, <<~MSG.squish if !values.is_a?(Array) && !values.is_a?(Range)
            Buckets must be an array or a range.
          MSG

          size ||= 1 if values.is_a?(Range)
          attribute = arel_table[attribute] unless ::Arel.arel_node?(attribute)
          self.buckets_value = [attribute, values, size, cast, as]
          self
        end

        # When performing calculations with buckets, this method add a grouping
        # clause to the query by the bucket values, and then adjust the keys
        # to match provided values
        def calculate(*)
          return super if buckets_value.blank?

          raise ArgumentError, <<~MSG.squish if group_values.present?
            Cannot calculate with buckets when there are already group values.
          MSG

          keys = buckets_keys
          self.group_values = [FN.group_by(build_buckets_node, :bucket)]
          super.transform_keys { |key| keys[key - 1] }
        end

        module Initializer
          # Hook into the output of records to make sure we group by the buckets
          def records
            return super if buckets_value.blank?

            keys = buckets_keys
            col = buckets_column
            super.group_by do |record|
              val = (record[col] || 0) - 1
              keys[val] if val >= 0 && val < keys.size
            end
          end
        end

        private

          # Hook arel build to add the column
          def build_arel(*)
            return super if buckets_value.blank? || select_values.present?

            self.select_extra_values += [build_buckets_node.as(buckets_column)]
            super
          end

          # Build the Arel node for the buckets function
          def build_buckets_node
            attribute, values, size, cast, * = buckets_value

            if values.is_a?(Range)
              FN.width_bucket(
                attribute,
                FN.bind_type(values.begin, name: 'bucket_start', cast: 'numeric'),
                FN.bind_type(values.end, name: 'bucket_end', cast: 'numeric'),
                FN.bind_type(size, name: 'bucket_size', cast: 'integer'),
              )
            else
              FN.width_bucket(attribute, ::Arel.array(values, cast: cast))
            end
          end

          # Returns the column used for buckets, if any
          def buckets_column
            buckets_value.last&.to_s || 'bucket'
          end

          # Transform a range into the proper keys for buckets
          def buckets_keys
            keys = buckets_value.second
            return keys unless keys.is_a?(Range)

            left = nil
            step = buckets_value.third
            step = (keys.end - keys.begin).fdiv(step)
            step = step.to_i if step.to_i == step
            keys.step(step).each_with_object([]) do |right, result|
              next left = right if left.nil?

              start, left = left, right
              result << Range.new(start, left, true)
            end
          end

      end

      Initializer.include(Buckets::Initializer)
    end
  end
end
