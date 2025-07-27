# frozen_string_literal: true

module Torque
  module PostgreSQL
    # Simplified module for creating arel functions. This is used internally
    # but can also be made available to other devs on their own projects
    module Function
      class << self

        # A facilitator to create a bind param that is fully compatible with
        # Arel and ActiveRecord
        def bind(*args)
          attr = ::ActiveRecord::Relation::QueryAttribute.new(*args)
          ::Arel::Nodes::BindParam.new(attr)
        end

        # Just a shortcut to create a bind param for a model attribute and a
        # value for it
        def bind_for(model, attribute, value)
          bind(attribute, value, model.attribute_types[attribute])
        end

        # Another shortcut, when we already have the arel attribute at hand
        def bind_with(arel_attribute, value)
          bind(arel_attribute.name, value, arel_attribute.type_caster)
        end

        # A facilitator to create an infix operation
        def infix(op, left, right)
          ::Arel::Nodes::InfixOperation.new(op, left, right)
        end

        # A facilitator to use several Infix operators to concatenate all the
        # provided arguments. Arguments won't be sanitized, as other methods
        # under this module
        def concat(*args)
          return args.first if args.one?
          args.reduce { |left, right| infix(:"||", left, right) }
        end

        # As of now, this indicates that it supports any direct calls, since
        # the idea is to simply map to an Arel function with the same name,
        # without checking if it actually exists
        def respond_to_missing?(*)
          true
        end

        # This method is used to catch any method calls that are not defined
        # in this module. It will simply return an Arel function with the same
        # name as the method called, passing all arguments to it, without
        # any sanitization
        def method_missing(name, *args, &block)
          ::Arel::Nodes::NamedFunction.new(name.to_s.upcase, args)
        end

      end
    end

    FN = Function
  end
end
