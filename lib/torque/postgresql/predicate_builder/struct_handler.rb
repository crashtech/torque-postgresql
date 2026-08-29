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
          # that whole documents are still compared as documents. Without a
          # value, a single document has properties that can be reached
          def candidate?(type, value = nil)
            return false if !type.is_a?(Adapter::OID::Struct) || type.is_a?(Adapter::OID::StructList)

            value.nil? || value.is_a?(::Hash)
          end
        end

        def initialize(predicate_builder)
          @predicate_builder = predicate_builder
        end

        def call(attribute, struct, value)
          table = table_for(attribute, struct)
          nodes = predicate_builder.with(table).build_from_hash(value.stringify_keys)

          ::Arel::Nodes::Grouping.new(nodes.reduce(:and))
        end

        # The properties of the document as the columns of a table, so that any
        # of them can be resolved by name. A document that no class describes
        # is open, which means any path into it is accepted, without a type
        def table_for(attribute, struct)
          raise ArgumentError, <<~MSG.squish if struct.is_a?(Adapter::OID::Struct) && struct.type != :jsonb
            Unable to build a condition over "#{attribute.name}" because json
            columns cannot be queried by their properties. Use jsonb instead.
          MSG

          @struct = struct
          PredicateTable.new(self, attribute, Arel::Nodes::Property)
        end

        # The node for a path into the document, resolved one property at a
        # time so that each level is typed by the class that declares it
        def property_for(attribute, struct, path)
          path.reduce(attribute) do |node, key|
            struct = node.type_caster if node.is_a?(Arel::Nodes::Property)
            table_for(node, struct)[key]
          end
        end

        # The type of a single property, plus what it has to be casted to once
        # it is extracted from the document as text
        def type_of(name)
          return [ActiveModel::Type.default_value, nil] unless @struct.is_a?(Adapter::OID::Struct)

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

            ActiveRecord::Base.with_connection { |c| c.type_to_sql(name) }
          end
      end
    end
  end
end
