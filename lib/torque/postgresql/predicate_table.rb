# frozen_string_literal: true

module Torque
  module PostgreSQL
    # Mimics ActiveRecord::TableMetadata so that the parts of a value that holds
    # other values, like the columns of a composite type or the properties of a
    # document, can be treated as the columns of the value they belong to. That
    # is what allows each of them to be handed back to the predicate builder
    #
    # The handler is the one that knows how to resolve a name, and the node is
    # the one that knows how to reach it
    class PredicateTable
      def initialize(handler, source, node)
        @handler = handler
        @source = source
        @node = node
      end

      def arel_table
        self
      end

      def [](name)
        @node.new(@source, name, *@handler.type_of(name))
      end

      def type(name)
        @handler.type_of(name).first
      end

      # Anything that gets here is meant to be resolved as a part of the value,
      # which is what +type_of+ is there to accept or reject
      def has_column?(*)
        true
      end

      def primary_key
        nil
      end

      def associated_with?(*)
        false
      end

      def aggregated_with?(*)
        false
      end

      def polymorphic_association?
        false
      end

      def through_association?
        false
      end
    end
  end
end
