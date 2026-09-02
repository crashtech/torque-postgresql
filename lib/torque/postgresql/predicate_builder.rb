# frozen_string_literal: true

require_relative 'predicate_builder/array_handler'

require_relative 'predicate_builder/composite_handler'
require_relative 'predicate_builder/ltree_handler'
require_relative 'predicate_builder/struct_handler'
require_relative 'predicate_builder/regexp_handler'
require_relative 'predicate_builder/arel_attribute_handler'
require_relative 'predicate_builder/enumerator_lazy_handler'

module Torque
  module PostgreSQL
    module PredicateBuilder
      ARRAY_OID = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array

      # The handler that serves a column, either to build a condition with the
      # given value or, without one, to resolve the parts of the column. The
      # ltree handler is picked by the column alone, composite and struct also
      # look at the value: a Hash means the parts, anything else the whole
      def self.handler_for(type, value = nil)
        if PostgreSQL.config.composite.enabled && CompositeHandler.candidate?(type, value)
          CompositeHandler
        elsif PostgreSQL.config.struct.enabled && StructHandler.candidate?(type, value)
          StructHandler
        elsif PostgreSQL.config.ltree.enabled && !value.nil? && LtreeHandler.candidate?(type)
          LtreeHandler
        end
      end

      def initialize(*)
        super

        handlers = Array.wrap(PostgreSQL.config.predicate_builder.enabled).inquiry

        if handlers.regexp?
          register_handler(Regexp, RegexpHandler.new(self))
        end

        if handlers.enumerator_lazy?
          register_handler(Enumerator::Lazy, EnumeratorLazyHandler.new(self))
        end

        if handlers.arel_attribute?
          register_handler(::Arel::Attributes::Attribute, ArelAttributeHandler.new(self))
        end
      end

      # Values described as a hash of columns or properties are turned into
      # conditions over the column that holds them. Whole values are left to
      # the regular handlers, so that they are compared as a single value, and
      # so is nil, which is a null check on every kind of column
      def build(attribute, value, operator = nil)
        return super if value.nil?

        type = Adapter::OID.unwrap(table.type(attribute.name))
        handler = PredicateBuilder.handler_for(type, value) || handler_for_path(attribute, value)
        return super if handler.nil?

        handler.new(self).call(attribute, type, value)
      end

      # A struct or composite column stands for the table of its own parts, so
      # a Hash given to order, group or pluck reaches a part the way where does
      def resolve_arel_attribute(table_name, column_name, &block)
        return super unless table.has_column?(table_name)

        type = Adapter::OID.unwrap(table.type(table_name))
        handler = PredicateBuilder.handler_for(type)
        return super if handler.nil?

        handler.new(self).table_for(table.arel_table[table_name], type)[column_name]
      end

      private

        # A Hash beneath a property that is not a document of its own is just
        # a deeper path, the way jsonb reads it, which is how an entry of an
        # array is reached
        def handler_for_path(attribute, value)
          return unless PostgreSQL.config.struct.enabled
          StructHandler if attribute.is_a?(Arel::Nodes::Property) && value.is_a?(::Hash)
        end
    end

    ::ActiveRecord::PredicateBuilder.prepend(PredicateBuilder)
  end
end
