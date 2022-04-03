# frozen_string_literal: true

require_relative 'relation/distinct_on'
require_relative 'relation/auxiliary_statement'
require_relative 'relation/inheritance'

require_relative 'relation/merger'

module Torque
  module PostgreSQL
    module Relation
      extend ActiveSupport::Concern

      include DistinctOn
      include AuxiliaryStatement
      include Inheritance

      SINGLE_VALUE_METHODS = [:itself_only]
      MULTI_VALUE_METHODS = [:distinct_on, :auxiliary_statements, :cast_records, :select_extra]
      VALUE_METHODS = SINGLE_VALUE_METHODS + MULTI_VALUE_METHODS

      ARColumn = ::ActiveRecord::ConnectionAdapters::PostgreSQL::Column

      # :nodoc:
      def select_extra_values; get_value(:select_extra); end
      # :nodoc:
      def select_extra_values=(value); set_value(:select_extra, value); end

      # Resolve column name when calculating models, allowing the column name to
      # be more complex while keeping the query selection quality
      def calculate(operation, column_name)
        column_name = resolve_column(column_name).first if column_name.is_a?(Hash)
        super(operation, column_name)
      end

      # Resolve column definition up to second value.
      # For example, based on Post model:
      #
      #   resolve_column(['name', :title])
      #   # Returns ['name', '"posts"."title"']
      #
      #   resolve_column([:title, {authors: :name}])
      #   # Returns ['"posts"."title"', '"authors"."name"']
      #
      #   resolve_column([{authors: [:name, :age]}])
      #   # Returns ['"authors"."name"', '"authors"."age"']
      def resolve_column(list, base = false)
        base = resolve_base_table(base)

        Array.wrap(list).map do |item|
          case item
          when String
            ::Arel.sql(klass.send(:sanitize_sql, item.to_s))
          when Symbol
            base ? base.arel_table[item] : klass.arel_table[item]
          when Array
            resolve_column(item, base)
          when Hash
            raise ArgumentError, 'Unsupported Hash for attributes on third level' if base
            item.map { |key, other_list| resolve_column(other_list, key) }
          else
            raise ArgumentError, "Unsupported argument type: #{value} (#{value.class})"
          end
        end.flatten
      end

      # Get the TableMetadata from a relation
      def resolve_base_table(relation)
        return unless relation

        table = predicate_builder.send(:table)
        if table.associated_with?(relation.to_s)
          table.associated_table(relation.to_s).send(:klass)
        else
          raise ArgumentError, "Relation for #{relation} not found on #{klass}"
        end
      end

      # Serialize the given value so it can be used in a condition tha involves
      # the given column
      def cast_for_condition(column, value)
        column = columns_hash[column.to_s] unless column.is_a?(ARColumn)
        caster = connection.lookup_cast_type_from_column(column)
        connection.type_cast(caster.serialize(value))
      end

      private

        def build_arel(*)
          arel = super
          arel.project(*select_extra_values) if select_values.blank?
          arel
        end

        # Compatibility method with 5.0
        unless ActiveRecord::Relation.method_defined?(:get_value)
          def get_value(name)
            @values[name] || ActiveRecord::QueryMethods::FROZEN_EMPTY_ARRAY
          end
        end

        # Compatibility method with 5.0
        unless ActiveRecord::Relation.method_defined?(:set_value)
          def set_value(name, value)
            assert_mutability!
            @values[name] = value
          end
        end

      module ClassMethods
        # Easy and storable way to access the name used to get the record table
        # name when using inheritance tables
        def _record_class_attribute
          @@record_class ||= Torque::PostgreSQL.config
            .inheritance.record_class_column_name.to_sym
        end

        # Easy and storable way to access the name used to get the indicater of
        # auto casting inherited records
        def _auto_cast_attribute
          @@auto_cast ||= Torque::PostgreSQL.config
            .inheritance.auto_cast_column_name.to_sym
        end
      end

      # When a relation is created, force the attributes to be defined,
      # because the type mapper may add new methods to the model. This happens
      # for the given model Klass and its inheritances
      module Initializer
        def initialize(klass, *, **)
          super

          klass.superclass.send(:relation) if klass.define_attribute_methods &&
            klass.superclass != ActiveRecord::Base && !klass.superclass.abstract_class?
        end
      end
    end

    # Include the methos here provided and then change the constants to ensure
    # the operation of ActiveRecord Relation
    ActiveRecord::Relation.include Relation
    ActiveRecord::Relation.prepend Relation::Initializer

    warn_level = $VERBOSE
    $VERBOSE = nil

    ActiveRecord::Relation::SINGLE_VALUE_METHODS       += Relation::SINGLE_VALUE_METHODS
    ActiveRecord::Relation::MULTI_VALUE_METHODS        += Relation::MULTI_VALUE_METHODS
    ActiveRecord::Relation::VALUE_METHODS              += Relation::VALUE_METHODS
    ActiveRecord::QueryMethods::VALID_UNSCOPING_VALUES += %i[cast_records itself_only
      distinct_on auxiliary_statements]

    $VERBOSE = warn_level
  end
end
