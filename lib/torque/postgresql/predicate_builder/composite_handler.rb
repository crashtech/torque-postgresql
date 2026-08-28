# frozen_string_literal: true

module Torque
  module PostgreSQL
    module PredicateBuilder
      # Turns a hash of columns into a proper set of conditions over a composite
      # column, handing each of them back to the predicate builder so that the
      # whole +where+ vocabulary works inside a composite
      class CompositeHandler
        class << self
          # Values that this handler knows how to deal with, checked before the
          # attribute itself because it is way cheaper
          def candidate?(value, type)
            return false unless Adapter::OID::Composite.from(type)

            case value
            when ::Hash, Attributes::Composite then true
            when ::Array then value.any? { |entry| candidate?(entry, type) }
            else false
            end
          end

          # Whether the value describes columns, instead of whole records
          def columns?(value)
            value.is_a?(::Hash) || (value.is_a?(::Array) && value.all?(::Hash))
          end
        end

        def initialize(predicate_builder)
          @predicate_builder = predicate_builder
        end

        def call(attribute, type, value)
          @composite = Adapter::OID::Composite.from(type)
          array = type.is_a?(ARRAY_OID)
          record = !self.class.columns?(value)

          return call_for_record(attribute, value, array) if record
          return call_for_array(attribute, value) if array

          conditions_for(attribute, value)
        end

        # The type of a single column of the composite type
        def type_of(name)
          columns = @composite.columns
          name = name.to_s

          raise ArgumentError, <<~MSG.squish unless columns.key?(name)
            Unable to build a condition for "#{name}" because it is not a
            column of the "#{@composite.name}" composite type.
          MSG

          [columns[name]]
        end

        private

          attr_reader :predicate_builder, :composite

          # Whole records cannot be sent as anonymous binds, because the
          # comparison operators resolve them to the +record+ pseudo type, so
          # they are always casted to the type they belong to
          def call_for_record(attribute, value, array)
            name = attribute.name
            cast = composite.name

            if !array && value.is_a?(::Array)
              records = value.map { |entry| FN.bind(name, entry, composite).pg_cast(cast) }
              return attribute.in(records)
            end

            return attribute.eq(FN.bind(name, value, composite).pg_cast(cast)) unless array

            if value.is_a?(::Array)
              list = FN.bind(name, value, ARRAY_OID.new(composite))
              return attribute.overlaps(list.pg_cast(cast, true))
            end

            entry = FN.bind(name, value, composite).pg_cast(cast)
            FN.infix(:"=", entry, FN.any(attribute))
          end

          # Entries of an array of composite values can only be matched one by
          # one, so the conditions are checked against each unnested entry
          def call_for_array(attribute, value)
            source = Arel::Nodes::Ref.new(composite.name)
            entries = ::Arel::Nodes::TableAlias.new(FN.unnest(attribute), composite.name)

            manager = ::Arel::SelectManager.new
            manager.from(entries)
            manager.project(::Arel.sql('1'))
            manager.where(conditions_for(source, value))
            manager.exists
          end

          # A list of values means that any of them is a match
          def conditions_for(source, value)
            return group_for(source, value) unless value.is_a?(::Array)

            groups = value.map { |entry| group_for(source, entry) }
            groups.reduce(:or)
          end

          def group_for(source, entry)
            entry = entry.to_h unless entry.is_a?(::Hash)
            table = PredicateTable.new(self, source, Arel::Nodes::Column)
            nodes = predicate_builder.with(table).build_from_hash(entry.stringify_keys)
            ::Arel::Nodes::Grouping.new(nodes.reduce(:and))
          end
      end
    end
  end
end
