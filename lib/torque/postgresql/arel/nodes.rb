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

        # A cross join, which PostgreSQL needs spelled out because an inner
        # join without a condition is a syntax error
        class CrossJoin < ::Arel::Nodes::Join
          def initialize(left, right = nil)
            super
          end
        end

        # An aliased FROM item. +definitions+ maps a column name to the SQL
        # type a function has to be told to return, +columns+ are the plain
        # names the alias exposes, +ordinality+ names the appended counter,
        # and +lateral+ is only needed when the source is a subquery
        class FromItem < ::Arel::Nodes::Binary
          attr_reader :columns, :definitions, :ordinality, :lateral

          alias name right

          def initialize(source, name, columns: nil, definitions: nil, ordinality: nil, lateral: false)
            @columns = Array.wrap(columns).presence&.freeze
            @definitions = definitions.presence&.freeze
            @ordinality = ordinality&.to_s
            @lateral = lateral

            super(source, name.to_s)
          end

          # The definitions can only be moved into the source when the counter
          # forces the +ROWS FROM+ form, since PostgreSQL refuses a column
          # definition list next to +WITH ORDINALITY+
          def rows_from?
            ordinality.present? && definitions.present?
          end

          # What the alias exposes, as name => type, where a +nil+ type means
          # the name stands on its own. Types are only spelled out here when
          # they have not been moved into the +ROWS FROM+ source.
          #
          # The list is all or nothing, because PostgreSQL matches it
          # positionally: a partial list silently renames the columns it does
          # reach instead of naming the ones it does not
          def alias_columns
            return {} if columns.nil? && definitions.nil?

            plain = rows_from? ? definitions.keys : columns
            result = plain.nil? ? definitions : plain.to_h { |name| [name.to_s, nil] }

            return result if ordinality.blank?
            result.merge(ordinality => nil)
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
