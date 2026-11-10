# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Relation
      module Segments

        # :nodoc:
        def segments_value
          @values.fetch(:segments, ::ActiveRecord::QueryMethods::FROZEN_EMPTY_HASH)
        end

        # :nodoc:
        def segments_value=(value)
          assert_modifiable!
          @values[:segments] = value
        end

        # Maps names to conditions so that the next calculation returns one
        # value per name, each aggregate filtered by its condition. Anything
        # that can become a relation is accepted as a condition, an array
        # applies each of its items in order, and +nil+ means the aggregate is
        # not filtered at all. For example:
        #
        #   User.segments(all: nil, adults: { age: 18.. }).count
        #   # Returns { all: 15, adults: 12 }
        #
        #   User.group(:role).segments(adults: { age: 18.. }).sum(:age)
        #   # Returns { 'visitor' => { adults: 480 }, ... }
        def segments(**map)
          spawn.segments!(**map)
        end

        # Like #segments, but modifies relation in place.
        def segments!(**map)
          predicates = map.to_h { |name, condition| [name, segment_predicate_for(name, condition)] }
          self.segments_value = segments_value.merge(predicates)
          self
        end

        private

          def execute_simple_calculation(operation, column_name, distinct)
            return super if segments_value.blank?

            execute_segments_calculation(operation, column_name, distinct)
          end

          def execute_grouped_calculation(operation, column_name, distinct)
            return super if segments_value.blank?

            execute_segments_calculation(operation, column_name, distinct)
          end

          def execute_segments_calculation(operation, column_name, distinct)
            column_name = primary_key if operation == 'count' && column_name == :all && distinct
            column = aggregate_column(column_name)
            aggregate = operation_over_aggregate_column(column, operation, distinct)

            relation = except(:group, :select).distinct!(false)
            relation.order_values = [] if group_values.empty?

            groups = relation.arel_columns(group_values)
            relation.group_values = groups

            result = skip_query_cache_if_necessary do
              klass.with_connection do |connection|
                relation.select_values = segments_projections(groups, aggregate, connection)
                connection.select_all(relation.arel, "#{klass.name} Segments", async: @async)
              end
            end

            result.then { |data| segments_result(data, groups, column, operation) }
          end

          def segments_projections(groups, aggregate, connection)
            tracker = ::ActiveRecord::Calculations::ColumnAliasTracker.new(connection)
            projections = groups.map do |group|
              name = tracker.alias_for(connection.visitor.compile(group).downcase)
              group.as(connection.quote_column_name(name))
            end

            segments_value.each_with_object(projections) do |(name, predicate), list|
              node = predicate.nil? ? aggregate.dup : aggregate.filter(predicate)
              list << node.as(connection.quote_column_name(name.to_s))
            end
          end

          def segments_result(data, groups, column, operation)
            type = column.try(:type_caster) || ::ActiveRecord::Type.default_value
            type = type.subtype if ::ActiveRecord::Enum::EnumType === type

            key_types = groups.each_with_index.to_h do |group, index|
              name = data.columns[index]
              key_type = group.try(:type_caster)
              key_type ||= type_for(group) { data.column_types.fetch(name, ::ActiveRecord::Type.default_value) }
              [name, key_type]
            end

            rows = data.cast_values(key_types)
            rows = rows.map { |value| [value] } if data.columns.size == 1

            rows = rows.to_h do |row|
              key = row.take(groups.size)
              key = key.first if key.size == 1

              values = row.drop(groups.size).map do |value|
                type_cast_calculated_value(value, operation, type)
              end

              [key, segments_value.keys.zip(values).to_h]
            end

            groups.empty? ? rows.values.first : rows
          end

          def segment_predicate_for(name, condition)
            return if !condition.is_a?(::ActiveRecord::Relation) && condition.blank?

            items = condition.is_a?(::Array) ? condition : [condition]
            relation = items.reduce(klass.unscoped) do |result, item|
              case item
              when ::ActiveRecord::Relation then result.merge(item)
              when Symbol then result.public_send(item)
              when Proc then item.arity.zero? ? result.instance_exec(&item) : item.call(result)
              else result.where(item)
              end
            end

            raise ArgumentError, <<~MSG.squish if relation.where_clause.empty?
              Segment #{name} does not filter anything, use nil for an unfiltered segment.
            MSG

            relation.where_clause.ast
          end

      end
    end
  end
end
