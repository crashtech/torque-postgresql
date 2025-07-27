# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Relation
      module Inheritance

        # :nodoc:
        def cast_records_value; get_value(:cast_records); end
        # :nodoc:
        def cast_records_value=(value); set_value(:cast_records, value); end

        # :nodoc:
        def itself_only_value; get_value(:itself_only); end
        # :nodoc:
        def itself_only_value=(value); set_value(:itself_only, value); end

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
          self.itself_only_value = true
          self
        end

        # Enables the casting of all returned records. The result will include
        # all the information needed to instantiate the inherited models
        #
        #   Activity.cast_records
        #   # The result list will have many different classes, for all
        #   # inherited models of activities
        def cast_records(*types, **options)
          spawn.cast_records!(*types, **options)
        end

        # Like #cast_records, but modifies relation in place
        def cast_records!(*types, **options)
          where!(regclass.pg_cast(:varchar).in(types.map(&:table_name))) if options[:filter]
          self.select_extra_values += [regclass.as(_record_class_attribute.to_s)]
          self.cast_records_value = (types.present? ? types : model.casted_dependents.values)
          self
        end

        private

          # Hook arel build to add any necessary table
          def build_arel(*)
            arel = super
            arel.only if self.itself_only_value === true
            build_inheritances(arel)
            arel
          end

          # Build all necessary data for inheritances
          def build_inheritances(arel)
            return unless self.cast_records_value.present?

            mergeable = inheritance_mergeable_attributes

            columns = build_inheritances_joins(arel, self.cast_records_value)
            columns = columns.map do |column, arel_tables|
              next arel_tables.first[column] if arel_tables.size == 1

              if mergeable.include?(column)
                FN.coalesce(*arel_tables.each_with_object(column).map(&:[])).as(column)
              else
                arel_tables.map { |table| table[column].as("#{table.left.name}__#{column}") }
              end
            end

            columns.push(build_auto_caster_marker(arel, self.cast_records_value))
            self.select_extra_values += columns.flatten if columns.any?
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

          def build_auto_caster_marker(arel, types)
            attribute = regclass.pg_cast(:varchar).in(types.map(&:table_name))
            attribute.as(self.class._auto_cast_attribute.to_s)
          end

          def regclass
            arel_table['tableoid'].pg_cast(:regclass)
          end

      end
    end
  end
end
