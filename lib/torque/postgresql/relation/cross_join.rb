# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Relation
      module CrossJoin

        Entry = ::Struct.new(:node, :table)

        class << self
          # Assemble the join node and the table that stands for what it
          # exposes, which is what makes the result reachable by name
          def build(source, as, columns, mode, with_ordinality, definitions = nil)
            columns = columns_for(source, columns)
            ordinality = ordinality_for(with_ordinality)
            validate_ordinality!(ordinality, columns, definitions)

            source, lateral = source_for(source, columns)
            item = Arel::Nodes::FromItem.new(source, as, columns: columns,
              definitions: definitions, ordinality: ordinality, lateral: lateral)

            Entry.new(join_for(mode, item), ::Arel::Table.new(as.to_s))
          end

          private

            # A list of documents describes its own columns, everything else
            # has to be told what they are
            def columns_for(source, columns)
              return columns if columns.present? || !source.is_a?(::Array)

              sample = source.first
              sample.keys if sample.is_a?(::Hash)
            end

            # The name of the counter column, which +true+ takes from the
            # configuration
            def ordinality_for(value)
              case value
              when true then PostgreSQL.config.cross_join.ordinality_column
              when ::Symbol, ::String then value
              end
            end

            # PostgreSQL matches the alias list positionally, so a list that
            # does not name every column silently renames the ones it reaches
            # instead of naming the counter. Without knowing the columns, the
            # only name that can be promised is the one PostgreSQL picks
            def validate_ordinality!(ordinality, columns, definitions)
              return if ordinality.blank? || columns.present? || definitions.present?
              return if ordinality.to_s == 'ordinality'

              raise ArgumentError, <<~MSG.squish
                Unable to name the ordinality column "#{ordinality}" because the
                columns of the source are unknown. Provide "columns:" so that
                all of them can be named, or let it be called "ordinality".
              MSG
            end

            # Only a subquery needs LATERAL, since it is a noise word in front
            # of a function and PostgreSQL lets those see the row already
            def source_for(source, columns)
              case source
              when ::ActiveRecord::Relation then [::Arel::Nodes::Grouping.new(source.arel.ast), true]
              when ::Arel::SelectManager then [::Arel::Nodes::Grouping.new(source.ast), true]
              when ::Array then [unnest_rows(source, columns), false]
              when ::Arel::Nodes::Node then [source, false]
              else
                raise ArgumentError, <<~MSG.squish
                  Unable to join "#{source.class}". Provide an Arel node, a
                  relation, or an Array of rows.
                MSG
              end
            end

            # Rows become one array per column, which costs a single bind for
            # each of them instead of one for every single value
            def unnest_rows(rows, columns)
              raise ArgumentError, 'Unable to join an empty list of rows.' if rows.empty?

              raise ArgumentError, <<~MSG.squish if columns.blank?
                Unable to name the columns of the given rows. Provide
                "columns:" or use a Hash for each row.
              MSG

              keys = columns.map(&:to_sym)
              values = rows.map { |row| row_values(row, keys) }
              args = values.transpose.map { |list| ::Arel.array(list) }
              FN.unnest(*args)
            end

            # Hash rows are read by name, so that they can be given in any
            # order, and their keys are compared as symbols because that is
            # not something the caller should have to match
            def row_values(row, keys)
              return ::Array.wrap(row) unless row.is_a?(::Hash)

              row.symbolize_keys.values_at(*keys)
            end

            # A lateral reference can only be combined with an inner or a left
            # join, and a cross join is how an inner one without a condition
            # has to be written
            def join_for(mode, item)
              case mode.to_sym
              when :cross then Arel::Nodes::CrossJoin.new(item)
              when :left
                on = ::Arel::Nodes::On.new(::Arel::Nodes::True.new)
                ::Arel::Nodes::OuterJoin.new(item, on)
              else
                raise ArgumentError, <<~MSG.squish
                  The "#{mode}" is not implemented as a join type. PostgreSQL
                  only combines a lateral reference with :cross or :left.
                MSG
              end
            end
        end

        # :nodoc:
        def cross_joins_value
          @values.fetch(:cross_joins, ::ActiveRecord::QueryMethods::FROZEN_EMPTY_HASH)
        end

        # :nodoc:
        def cross_joins_value=(value)
          assert_modifiable!
          @values[:cross_joins] = value
        end

        # Joins the query against a set produced by the given source, which
        # can be an Arel node, another relation, or a list of rows. The result
        # is reachable by the name given to +as+. For example:
        #
        #   User.cross_join(FN.generate_series(1, 5), as: :sample, columns: %i[value])
        #   # Returns 5 rows for each user
        #
        #   User.cross_join([{ id: 1, label: 'a' }], as: :labels)
        #   # Returns the rows of the list combined with each user
        def cross_join(source, **xargs)
          spawn.cross_join!(source, **xargs)
        end

        # Like #cross_join, but modifies relation in place.
        def cross_join!(source, as:, columns: nil, mode: :cross, with_ordinality: false)
          entry = CrossJoin.build(source, as, columns, mode, with_ordinality)
          self.cross_joins_value = cross_joins_value.merge(as.to_sym => entry)
          self
        end

        private

          # Hook arel build to add the joins, which is done here instead of
          # through the join values because those are inspected by Rails for
          # table aliases, and these sources have no table to inspect
          def build_arel(*)
            arel = super
            return arel if cross_joins_value.blank?

            nodes = cross_joins_value.each_value.map(&:node)
            arel.join_sources.concat(nodes)
            arel
          end

        # The merger is loaded with the relation, so the part that knows about
        # this feature is coordinated from here
        module Merger
          def merge # :nodoc:
            result = super
            merge_cross_joins
            result
          end

          private

            def merge_cross_joins
              return unless relation.is_a?(Relation::CrossJoin)
              return if other.cross_joins_value.blank?

              relation.cross_joins_value =
                relation.cross_joins_value.merge(other.cross_joins_value)
            end
        end

      end

      ::ActiveRecord::Relation::Merger.prepend(CrossJoin::Merger)

      ::ActiveRecord::Relation::SINGLE_VALUE_METHODS.push(:cross_joins)
      ::ActiveRecord::Relation::VALUE_METHODS.push(:cross_joins)
      ::ActiveRecord::QueryMethods::VALID_UNSCOPING_VALUES.add(:cross_joins)
    end
  end
end
