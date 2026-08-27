# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Attributes
      # A pattern that matches label paths, as described by the +lquery+ data
      # type. It holds the pure items of the pattern: labels as Strings, +:any+
      # for a star, a Range for a quantified star and an Array for a group of
      # alternatives
      class LQuery
        include Enumerable

        MARKERS = /[*|!{}@%]/

        attr_reader :items

        delegate :inspect, to: :to_s
        delegate :each, :size, :empty?, :[], to: :items

        def self.[](*items)
          new(items)
        end

        def initialize(value = nil, sanitize: true)
          @items = type.items_for(value, sanitize: sanitize).freeze
        end

        def to_s
          type.serialize(self)
        end

        # Whether any item asks for a pattern instead of a plain path, which is
        # what makes a condition use +~+ instead of +=+
        def pattern?
          items.any? { |item| !item.is_a?(::String) || item.match?(MARKERS) }
        end

        def ==(other)
          other = other.items if other.is_a?(self.class)
          other.is_a?(::Array) && items == other
        end
        alias eql? ==

        def hash
          items.hash
        end

        private

          def type
            Adapter::OID::Lquery.new
          end
      end
    end

    LQuery = Attributes::LQuery
  end
end
