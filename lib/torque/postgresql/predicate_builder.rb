# frozen_string_literal: true

require_relative 'predicate_builder/array_handler'

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
    end

    ::ActiveRecord::PredicateBuilder.prepend(PredicateBuilder)
  end
end
