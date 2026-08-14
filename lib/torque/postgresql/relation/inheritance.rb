# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Relation
      module Inheritance

        # :nodoc:
        def expand_records_values
          @values.fetch(:expand_records, FROZEN_EMPTY_ARRAY)
        end
        # :nodoc:
        def expand_records_values=(value)
          assert_modifiable!
          @values[:expand_records] = value
        end

        # :nodoc:
        def expand_records_eager_load_value
          @values.fetch(:expand_records_eager_load, nil)
        end
        # :nodoc:
        def expand_records_eager_load_value=(value)
          assert_modifiable!
          @values[:expand_records_eager_load] = value
        end

        # :nodoc:
        def expand_records_scoped_value
          @values.fetch(:expand_records_scoped, nil) || {}
        end
        # :nodoc:
        def expand_records_scoped_value=(value)
          assert_modifiable!
          @values[:expand_records_scoped] = value
        end

        # :nodoc:
        def itself_only_value
          @values.fetch(:itself_only, nil)
        end
        # :nodoc:
        def itself_only_value=(value)
          assert_modifiable!
          @values[:itself_only] = value
        end

        RECORD_CLASS_TOKEN = :_regclass

        delegate :quote_table_name, :quote_column_name, to: :connection

        # Specify that the results should come only from the table that the
        # entries were created on. For example:
        #
        #   Activity.itself_only
        #   # Does not return entries for inherited tables
        def itself_only
          spawn.itself_only!
        end

        # Like #itself_only, but modifies relation in place.
        def itself_only!(*)
          raise_itself_only_conflict! if expand_records_values.present?

          self.itself_only_value = true
          self
        end

        # Load the columns that only exist on the inherited tables, so that
        # records come out complete and writable. Defaults to every dependent
        # that adds columns
        #
        #   Activity.expand_records
        #   # Runs one additional query per inherited table
        #
        #   Activity.expand_records(ActivityBook, eager_load: true)
        #   # Runs a single query using outer joins
        def expand_records(*types, **options)
          spawn.expand_records!(*types, **options)
        end

        # Like #expand_records, but modifies relation in place
        def expand_records!(*types, eager_load: false, filter: false)
          raise_itself_only_conflict! if itself_only_value === true

          types = types.presence || model.inheritance_expandable_dependents.values

          where!(regclass.pg_cast(:varchar).in(types.map(&:table_name))) if filter
          self.expand_records_values = types
          self.expand_records_eager_load_value = eager_load
          self
        end

        # Accept the record class marker as a column, which is the only way an
        # explicit selection can still produce casted records
        #
        #   Activity.select(:_regclass, :id, :title)
        def select(*fields)
          return super if fields.empty?
          return super(*fields, build_record_class_marker) if fields.delete(RECORD_CLASS_TOKEN)

          super
        end

        private

          def raise_itself_only_conflict!
            raise InheritanceError.new(<<~MSG.squish)
              Reading from ONLY a table never returns records from its
              inherited tables, so itself_only and expand_records cannot be
              combined.
            MSG
          end

          # Hook arel build to add any necessary table
          def build_arel(*)
            arel = super
            arel.only if self.itself_only_value === true

            arel.project(build_record_class_marker) if inheritance_discriminated?
            build_inheritances(arel) if self.expand_records_eager_load_value
            arel
          end

          def inheritance_discriminated?
            return false if self.itself_only_value === true
            return false if select_values.present?
            return false unless from_clause.empty?

            model.physically_inheritances?
          end

          def build_record_class_marker
            regclass.as(_record_class_column_name)
          end

          # Build all necessary data for inheritances
          def build_inheritances(arel)
            return if self.expand_records_values.empty?

            columns = build_inheritances_joins(arel, self.expand_records_values)
            # The joins are still needed, but an explicit select owns the projection
            return if columns.empty? || select_values.present?

            mergeable = inheritance_mergeable_attributes
            projections = columns.map do |column, arel_tables|
              next arel_tables.first[column] if arel_tables.size == 1

              if mergeable.include?(column)
                FN.coalesce(*arel_tables.each_with_object(column).map(&:[])).as(column)
              else
                arel_tables.map { |table| table[column].as("#{table.left.name}__#{column}") }
              end
            end

            arel.project(*projections.flatten)
          end

          # Build as many left outer join as necessary for each dependent table
          def build_inheritances_joins(arel, types)
            columns = Hash.new{ |h, k| h[k] = [] }
            base_on_key = model.arel_table[primary_key]
            base_attributes = model.attribute_names

            # Iterate over each casted dependent calculating the columns
            types.each.with_index do |model, idx|
              join_table = model.arel_table.alias("\"i_#{idx}\"")
              arel.outer_join(join_table).on(base_on_key.eq(join_table[primary_key]))
              (model.attribute_names - base_attributes).each do |column|
                columns[column] << join_table
              end
            end

            # Return the list of needed columns
            columns.default_proc = nil
            columns
          end

          def regclass
            arel_table['tableoid'].pg_cast(:regclass)
          end

        module Expansion
          def preload_associations(records)
            super
            return if expand_records_scoped_value.blank?

            expand_records_scoped_value.each do |base_model, targets|
              preloaded_association_names.each do |name|
                reflection = model.reflect_on_association(name)
                next if reflection.nil? || reflection.polymorphic? || !(reflection.klass <= base_model)

                loaded = records.flat_map { |record| record.association(name).target }
                PostgreSQL::Inheritance::Expander.new(reflection.klass, loaded.compact, targets).call
              end
            end
          end

          private

            # Records only carry the columns of the queried table, so
            # expanding has to happen after they have been instantiated
            def exec_queries
              records = super
              warn_about_missing_record_class(records)
              return records if expand_records_values.empty? || expand_records_eager_load_value

              PostgreSQL::Inheritance::Expander.new(model, records, expand_records_values).call
              records.each(&:readonly!) if readonly_value
              records
            end

            def preloaded_association_names
              list = preload_values + (eager_loading? ? [] : includes_values)
              list.flat_map { |entry| entry.is_a?(Hash) ? entry.keys : entry }
            end

            # Warn once per query that actually lost the real class, instead of
            # once per explicit select that merely omits the marker
            def warn_about_missing_record_class(records)
              return unless model.physically_inheritances?
              return if records.empty? || group_values.present? || distinct_value || select_values.empty?
              return unless from_clause.empty?
              return if itself_only_value === true
              return if select_values.any? { |value| record_class_marker?(value) }
              return if records.any? { |record| record.class != model }

              warn(<<~MSG.squish)
                #{model.name} was queried with an explicit select that omits
                :_regclass, so its records will not be instantiated as their
                real class.
              MSG
            end

            def record_class_marker?(value)
              return value.right.to_s == _record_class_column_name if value.is_a?(::Arel::Nodes::As)
              value.is_a?(String) && value.include?(_record_class_column_name)
            end

        end
      end
    end
  end
end
