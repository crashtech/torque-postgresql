# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Attributes
      class Lazy < BasicObject

        def initialize(klass, *values)
          @klass, @values = klass, values
        end

        def ==(other)
          other.nil?
        end

        def nil?
          true
        end

        def inspect
          'nil'
        end

        def __class__
          Lazy
        end

        def method_missing(name, *args, &block)
          @klass.new(*@values).send(name, *args, &block)
        end

      end
    end
  end
end
