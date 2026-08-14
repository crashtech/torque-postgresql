# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Inheritance
      class Expander

        def initialize(model, records, targets)
          @model = model
          @records = records
          @targets = targets
        end

        # Load the columns that are missing from each partial record using one
        # query per inherited table
        def call
          pending.each do |klass, records|
            amend(klass, records, fetch(klass, records.map(&:id)))
          end

          @records
        end

        private

          attr_reader :model, :targets

          def pending
            @records.select do |record|
              record.partial_record? && targets.include?(record.class)
            end.group_by(&:class)
          end

          def extra_columns(klass)
            klass.attribute_names - model.attribute_names
          end

          def fetch(klass, ids)
            columns = [klass.primary_key, *extra_columns(klass)]
            table = klass.arel_table
            query = klass.unscoped.itself_only.select(*columns.map { |name| table[name] })

            klass.lease_connection.select_all(
              query.where(klass.primary_key => ids).arel,
              "#{klass.name} Expand",
            ).to_a.index_by { |row| row[klass.primary_key] }
          end

          def amend(klass, records, rows)
            columns = extra_columns(klass)

            records.each do |record|
              row = rows[record.id]
              next if row.nil?

              attributes = record.instance_variable_get(:@attributes)
              columns.each { |name| attributes.write_from_database(name, row[name]) }

              record.send(:mark_as_full_record!)
            end
          end

      end
    end
  end
end
