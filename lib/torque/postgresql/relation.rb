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
      MULTI_VALUE_METHODS = [:distinct_on, :auxiliary_statements, :cast_records]
      VALUE_METHODS = SINGLE_VALUE_METHODS + MULTI_VALUE_METHODS

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
            ::Arel::Nodes::SqlLiteral.new(klass.send(:sanitize_sql, item.to_s))
          when Symbol
            base ? base.arel_attribute(item) : klass.arel_attribute(item)
          when Array
            resolve_column(item, base)
          when Hash
            raise ArgumentError, "Unsupported Hash for attributes on third level" if base
            item.map do |key, other_list|
              other_list = [other_list] unless other_list.kind_of? Enumerable
              resolve_column(other_list, key)
            end
          else
            raise ArgumentError, "Unsupported argument type: #{value} (#{value.class})"
          end
        end.flatten
      end

      # Get the TableMetadata from a relation
      def resolve_base_table(relation)
        return unless relation

        table = predicate_builder.send(:table)
        if table.associated_with?(relation)
          table.associated_table(relation).send(:klass)
        else
          raise ArgumentError, "Relation for #{relation} not found on #{klass}"
        end
      end

      private

        def dynamic_selection
          @dynamic_selection ||= []
        end

        def build_arel(*)
          arel = super
          arel.project(*dynamic_selection) if select_values.blank? && dynamic_selection.any?
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
        def initialize(klass, *)
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

    ActiveRecord::Relation::SINGLE_VALUE_METHODS  += Relation::SINGLE_VALUE_METHODS
    ActiveRecord::Relation::MULTI_VALUE_METHODS   += Relation::MULTI_VALUE_METHODS
    ActiveRecord::Relation::VALUE_METHODS         += Relation::VALUE_METHODS
    ActiveRecord::QueryMethods::VALID_UNSCOPING_VALUES += [:cast_records, :itself_only,
      :distinct_on, :auxiliary_statements]

    if ActiveRecord::QueryMethods.const_defined?('DEFAULT_VALUES')
      Relation::SINGLE_VALUE_METHODS.each do |value|
        ActiveRecord::QueryMethods::DEFAULT_VALUES[value] = nil \
          if ActiveRecord::QueryMethods::DEFAULT_VALUES[value].nil?
      end

      Relation::MULTI_VALUE_METHODS.each do |value|
        ActiveRecord::QueryMethods::DEFAULT_VALUES[value] ||= \
          ActiveRecord::QueryMethods::FROZEN_EMPTY_ARRAY
      end
    end

    $VERBOSE = warn_level
  end
end
