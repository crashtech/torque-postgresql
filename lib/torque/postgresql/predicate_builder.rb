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
      # the regular handlers, so that they are compared as a single value
      def build(attribute, value, operator = nil)
        type = table.type(attribute.name)
        handler = handler_for_document(type, value)
        return super if handler.nil?

        handler.new(self).call(attribute, type, value)
      end

      private

        # Only the ltree handler is picked by the attribute alone. Composite
        # could follow, since whole values already bind through the type and
        # would only need the same nil guard, but struct cannot: a Hash means
        # the properties of the document and any other value means the whole
        # document, and nothing on the attribute tells those two apart
        def handler_for_document(type, value)
          if PostgreSQL.config.composite.enabled && CompositeHandler.candidate?(value, type)
            CompositeHandler
          elsif PostgreSQL.config.struct.enabled && StructHandler.candidate?(value, type)
            StructHandler
          elsif PostgreSQL.config.ltree.enabled && LtreeHandler.candidate?(type)
            LtreeHandler
          end
        end
    end

    ::ActiveRecord::PredicateBuilder.prepend(PredicateBuilder)
  end
end
