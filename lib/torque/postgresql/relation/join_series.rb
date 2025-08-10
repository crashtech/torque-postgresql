# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Relation
      module JoinSeries

        # Create the proper arel join
        class << self
          def build(relation, range, with: nil, as: :series, step: nil, time_zone: nil, mode: :inner, &block)
            validate_build!(range, step)

            args = [bind_value(range.begin), bind_value(range.end)]
            args << bind_value(step) if step
            args << bind_value(time_zone) if time_zone

            result = Arel::Nodes::Ref.new(as.to_s)
            func = FN.generate_series(*args).as(as.to_s)
            condition = build_join_on(result, relation, with, &block)
            arel_join(mode).new(func, func.create_on(condition))
          end

          private

            # Make sure we have a viable range
            def validate_build!(range, step)
              raise ArgumentError, <<~MSG.squish unless range.is_a?(Range)
                Value must be a Range.
              MSG

              raise ArgumentError, <<~MSG.squish if range.begin.nil?
                Beginless Ranges are not supported.
              MSG

              raise ArgumentError, <<~MSG.squish if range.end.nil?
                Endless Ranges are not supported.
              MSG

              raise ArgumentError, <<~MSG.squish if !range.begin.is_a?(Numeric) && step.nil?
                missing keyword: :step
              MSG
            end

            # Creates the proper bind value
            def bind_value(value)
              case value
              when Integer
                FN.bind_type(value, :integer, name: 'series', cast: 'integer')
              when Float
                FN.bind_type(value, :float, name: 'series', cast: 'numeric')
              when String
                FN.bind_type(value, :string, name: 'series', cast: 'text')
              when ActiveSupport::TimeWithZone
                FN.bind_type(value, :time, name: 'series', cast: 'timestamptz')
              when Time
                FN.bind_type(value, :time, name: 'series', cast: 'timestamp')
              when DateTime
                FN.bind_type(value, :datetime, name: 'series', cast: 'timestamp')
              when ActiveSupport::Duration
                type = Adapter::OID::Interval.new
                FN.bind_type(value, type, name: 'series', cast: 'interval')
              when Date then bind_value(value.to_time(:utc))
              when ::Arel::Attributes::Attribute then value
              else
                raise ArgumentError, "Unsupported value type: #{value.class}"
              end
            end

            # Get the class of the join on arel
            def arel_join(mode)
              case mode.to_sym
              when :inner then ::Arel::Nodes::InnerJoin
              when :left  then ::Arel::Nodes::OuterJoin
              when :right then ::Arel::Nodes::RightOuterJoin
              when :full  then ::Arel::Nodes::FullOuterJoin
              else
                raise ArgumentError, <<-MSG.squish
                  The '#{mode}' is not implemented as a join type.
                MSG
              end
            end

            # Build the join on clause
            def build_join_on(result, relation, with)
              raise ArgumentError, <<~MSG.squish if with.nil? && !block_given?
                missing keyword: :with
              MSG

              return yield(result, relation.arel_table) if block_given?

              result.eq(with.is_a?(Symbol) ? relation.arel_table[with.to_s] : with)
            end
        end

        # Creates a new join based on PG +generate_series()+ function. It is
        # based on ranges, supports numbers and dates (as per PG documentation),
        # custom stepping, time zones, and more. This simply coordinates the
        # initialization of the the proper join
        def join_series(range, **xargs, &block)
          spawn.join_series!(range, **xargs, &block)
        end

        # Like #join_series, but modifies relation in place.
        def join_series!(range, **xargs, &block)
          self.joins_values |= [JoinSeries.build(self, range, **xargs, &block)]
          self
        end

      end
    end
  end
end
