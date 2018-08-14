module Torque
  module PostgreSQL
    module Relation
      module Inheritance

        def cast_records_value; get_value(:cast_records); end
        def cast_records_value=(value); set_value(:cast_records, value); end

        def from_only_value; get_value(:from_only); end
        def from_only_value=(value); set_value(:from_only, value); end

        delegate :quote_table_name, :quote_column_name, to: :connection

        # Specify that the results should come only from the table that the
        # entries were created on. For example:
        #
        #   Activity.from_only
        #   # Does not return entries for inherited tables
        def from_only
          spawn.from_only!
        end

        # Like #from_only, but modifies relation in place.
        def from_only!(*)
          self.from_only_value = true
          self
        end

        # Enables the casting of all returned records. The result will include
        # all the information needed to instantiate the inherited models
        #
        #   Activity.cast_records
        #   # The result list will have many different classes, for all
        #   # inherited models of activities
        def cast_records
          spawn.cast_records!
        end

        # Like #cast_records, but modifies relation in place
        def cast_records!(*)
          with!(model.record_class)
          self.cast_records_value = true
          self
        end

        private

          # Hook arel build to add any necessary table
          def build_arel
            arel = super
            arel.only if self.from_only_value
            build_inheritances(arel)
            arel
          end

          # Build all necessary data for inheritances
          def build_inheritances(arel)
            return unless self.cast_records_value

            columns = build_inheritances_joins(arel)
            columns = columns.map do |column, arel_tables|
              next arel_tables.first[column] if arel_tables.size == 1
              list = arel_tables.each_with_object(column).map(&:[])
              ::Arel::Nodes::NamedFunction.new('COALESCE', list).as(column)
            end

            columns.push(model.auto_caster_marker)
            arel.project(*columns) if columns.any?
          end

          # Build as many left outer join as necessary for each dependent table
          def build_inheritances_joins(arel)
            columns = Hash.new{ |h, k| h[k] = [] }
            primary_key = quoted_primary_key
            base_attributes = model.attribute_names

            # Iterate over each casted dependent calculating the columns
            model.casted_dependents.each do |_, model|
              arel.outer_join(model.arel_table).using(primary_key)
              (model.attribute_names - base_attributes).each do |column|
                columns[column] << model.arel_table
              end
            end

            # Return the list of needed columns
            columns.default_proc = nil
            columns
          end

      end
    end
  end
end
