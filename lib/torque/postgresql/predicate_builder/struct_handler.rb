# frozen_string_literal: true

module Torque
  module PostgreSQL
    module PredicateBuilder
      # Turns a hash of properties into a proper set of conditions over the
      # document that holds them, handing each of them back to the predicate
      # builder so that the whole +where+ vocabulary works inside a struct
      class StructHandler
        # Properties are extracted as text, so only the ones whose type has a
        # counterpart on the database are casted before being compared
        PLAIN_TYPES = %i[string text].freeze

        class << self
          # Only a hash describes properties, everything else is left alone so
          # that whole documents are still compared as documents
          def candidate?(value, type)
            value.is_a?(::Hash) && type.is_a?(Adapter::OID::Struct) &&
              !type.is_a?(Adapter::OID::StructList)
          end
        end

        def initialize(predicate_builder)
          @predicate_builder = predicate_builder
        end

        def call(attribute, struct, value)
          raise ArgumentError, <<~MSG.squish unless struct.type == :jsonb
            Unable to build a condition over "#{attribute.name}" because json
            columns cannot be queried by their properties. Use jsonb instead.
          MSG

          @struct = struct
          table = PredicateTable.new(self, attribute, Arel::Nodes::Property)
          nodes = predicate_builder.with(table).build_from_hash(value.stringify_keys)

          ::Arel::Nodes::Grouping.new(nodes.reduce(:and))
        end

        # The type of a single property, plus what it has to be casted to once
        # it is extracted from the document as text
        def type_of(name)
          klass = @struct.klass
          name = name.to_s

          raise ArgumentError, <<~MSG.squish if klass.strict? && !klass.attribute_names.include?(name)
            Unable to build a condition for "#{name}" because it is not a
            declared property of #{klass.name}.
          MSG

          type = klass.attribute_types[name]
          [type, cast_for(type)]
        end

        private

          attr_reader :predicate_builder

          def cast_for(type)
            name = type&.type
            return if name.nil? || PLAIN_TYPES.include?(name)

            ActiveRecord::Base.connection.type_to_sql(name)
          end
      end
    end
  end
end
