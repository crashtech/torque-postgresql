# frozen_string_literal: true

module Torque
  module PostgreSQL
    module PredicateBuilder
      # Serves every column of the ltree extension. A value of the same kind as
      # the column is an equality, a value of the opposite kind is a match, and
      # an Array is a list of values as soon as its first entry is a whole one
      class LtreeHandler
        class << self
          def candidate?(type)
            column_of(type).is_a?(Adapter::OID::Ltree)
          end

          def column_of(type)
            type.is_a?(ARRAY_OID) ? type.subtype : type
          end
        end

        def initialize(predicate_builder)
          @predicate_builder = predicate_builder
        end

        def call(attribute, type, value)
          @attribute = attribute
          @column = self.class.column_of(type)
          @array = type.is_a?(ARRAY_OID)
          @list = list?(value)

          values = list ? value : [value]
          pattern = values.any? { |entry| lquery.cast(entry)&.pattern? }
          pattern == lquery_column? ? equality(values) : match(values)
        end

        private

          attr_reader :attribute, :column, :array, :list

          def list?(value)
            return false unless value.is_a?(::Array)

            first = value.first
            value.empty? || first.is_a?(::Array) || first.is_a?(LTree) || first.is_a?(LQuery)
          end

          def lquery_column?
            column.is_a?(Adapter::OID::Lquery)
          end

          def lquery
            Adapter::OID::Lquery.new
          end

          def ltree
            Adapter::OID::Ltree.new
          end

          # Bound as the value the type produces, since Rails deep dups a raw
          # value before compiling the query, and a dup of a record has no id
          def bind(value, type)
            FN.bind(attribute.name, type.cast(value), type)
          end

          # PostgreSQL defines no equality operator for lquery, so a pattern
          # column is compared by its text form
          def equality(values)
            target = lquery_column? ? attribute.pg_cast('text', array) : attribute
            return single_equality(target, bind(values.first, column)) unless list
            return empty_equality(target) if values.empty?
            return target.overlaps(bind(values, ARRAY_OID.new(column))) if array

            binds = values.map { |entry| bind(entry, column) }
            target.in(binds)
          end

          def single_equality(target, bind)
            return target.eq(bind) unless array

            FN.infix(:"=", bind, FN.any(target))
          end

          def empty_equality(target)
            return target.in([]) unless array

            FN.cardinality(attribute).eq(0)
          end

          def match(values)
            other = lquery_column? ? ltree : lquery
            cast = other.type.to_s
            return single_match(bind(values.first, other).pg_cast(cast)) unless list

            list_match(bind(values, ARRAY_OID.new(other)).pg_cast(cast, true))
          end

          # PostgreSQL defines ~ for every pair except lquery[] against ltree
          def single_match(bind)
            return attribute.matches_lquery(bind) unless array && lquery_column?

            FN.infix(:"~", bind, FN.any(attribute))
          end

          # PostgreSQL defines ? for every pair except lquery against ltree[]
          def list_match(binds)
            return attribute.matches_any_lquery(binds) if array || !lquery_column?

            FN.infix(:"~", attribute, FN.any(binds))
          end
      end
    end
  end
end
