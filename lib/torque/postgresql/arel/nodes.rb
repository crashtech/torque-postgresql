# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Arel
      module Nodes

        class Cast < ::Arel::Nodes::Binary
          include ::Arel::Expressions
          include ::Arel::Predications
          include ::Arel::AliasPredication
          include ::Arel::OrderPredications
          include ::Arel::Math

          def initialize(left, right, array = false)
            right = right.to_s.dup
            right << '[]' if array
            super left, right
          end
        end

        # Accessing a single column of a composite value, which behaves like an
        # attribute of the composite type it belongs to
        class Column < ::Arel::Nodes::Binary
          include ::Arel::Expressions
          include ::Arel::Predications
          include ::Arel::AliasPredication
          include ::Arel::OrderPredications
          include ::Arel::Math

          attr_reader :type_caster
          alias name right

          def initialize(source, name, type_caster)
            @type_caster = type_caster
            super(source, name.to_s)
          end

          def able_to_type_cast?
            true
          end

          def type_cast_for_database(value)
            type_caster.serialize(value)
          end
        end

        # Accessing a single property of a document, at any depth, casted to
        # the type that the class declares for it
        class Property < ::Arel::Nodes::Binary
          include ::Arel::Expressions
          include ::Arel::Predications
          include ::Arel::AliasPredication
          include ::Arel::OrderPredications
          include ::Arel::Math

          attr_reader :type_caster, :cast

          alias path right

          # Reaching a property of another one simply adds up to the path, so
          # that a single node always holds the whole way to it
          def initialize(source, key, type_caster, cast = nil)
            @type_caster = type_caster
            @cast = cast

            return super(source.left, source.path + [key.to_s]) if source.is_a?(Property)
            super(source, [key.to_s])
          end

          def name
            right.last
          end

          def able_to_type_cast?
            true
          end

          def type_cast_for_database(value)
            type_caster.serialize(value)
          end
        end

        class Ref < ::Arel::Nodes::Unary
          attr_reader :reference
          alias to_s expr

          def initialize(expr, reference = nil)
            @reference = reference
            super expr
          end

          def as(other)
            @reference&.as(other) || super
          end
        end

      end

      ::Arel.define_singleton_method(:array) do |*values, cast: nil|
        values = values.first if values.size.eql?(1) && values.first.is_a?(::Enumerable)
        result = ::Arel::Nodes.build_quoted(values)
        result = result.pg_cast(cast, true) if cast.present?
        result
      end

      ::Arel::Nodes::Function.include(::Arel::Math)
    end
  end
end
