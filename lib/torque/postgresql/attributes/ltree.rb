# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Attributes
      # A label path, as stored by the +ltree+ data type. It holds the plain
      # list of labels, so it enumerates like any other list, and an +ltree[]+
      # column simply becomes an Array of these
      class LTree
        include Enumerable

        attr_reader :items

        delegate :inspect, to: :to_s
        delegate :each, :size, :empty?, :[], to: :items
        alias depth size

        class << self
          def [](*items)
            new(items)
          end

          # Whether the object knows how to describe itself as a path, which is
          # what allows any class to be used where a path is expected
          def compatible?(value)
            method = PostgreSQL.config.ltree.compatible_method
            method.present? && value.respond_to?(method)
          end

          # The path that the object describes for itself
          def compatible(value)
            method = PostgreSQL.config.ltree.compatible_method
            value.public_send(method) if compatible?(value)
          end
        end

        def initialize(value = nil, sanitize: true)
          @items = type.items_for(value, sanitize: sanitize).freeze
        end

        def to_s
          type.serialize(self)
        end

        def ==(other)
          other = other.items if other.is_a?(self.class)
          other.is_a?(::Array) && items == other
        end
        alias eql? ==

        def hash
          items.hash
        end

        def root?
          size <= 1
        end

        def root
          self.class.new(items.first(1), sanitize: false)
        end

        def parent
          self.class.new(items[0..-2], sanitize: false) unless root?
        end

        def /(other)
          self.class.new(items + self.class.new(other).items, sanitize: false)
        end

        alias_method :+, :/

        # Same as the +@>+ operator, which includes the path itself
        def ancestor_of?(other)
          other = self.class.new(other).items
          size <= other.size && other.first(size) == items
        end
        alias covers? ancestor_of?

        # Same as the +<@+ operator, which includes the path itself
        def descendant_of?(other)
          self.class.new(other).ancestor_of?(self)
        end
        alias covered_by? descendant_of?

        # The longest common ancestor, which never includes the last label of
        # any of the paths, exactly like PostgreSQL's own +lca+
        def lca(*others)
          paths = [self, *others].map { |path| self.class.new(path).items[0..-2] }
          result = paths.shift
          paths.each { |path| result = common_prefix(result, path) }
          self.class.new(result, sanitize: false)
        end

        def index_of(subpath, offset = 0)
          subpath = self.class.new(subpath).items
          offset += size if offset.negative?
          return -1 if subpath.empty? || offset.negative?

          range = offset..(size - subpath.size)
          position = range.find { |i| items[i, subpath.size] == subpath }
          position || -1
        end

        private

          def type
            Adapter::OID::Ltree.new
          end

          def common_prefix(one, other)
            limit = [one.size, other.size].min
            size = (0...limit).find { |i| one[i] != other[i] }
            one.first(size || limit)
          end
      end
    end

    LTree = Attributes::LTree
  end
end
