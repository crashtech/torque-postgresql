# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Attributes
      # A label path, as stored by the +ltree+ data type. It is an Array of
      # labels, so it flows through Ruby like any other list, which also means
      # that an +ltree[]+ column simply becomes an Array of these
      class LTree < Array
        LABEL = /\A[[:alnum:]_-]+\z/

        alias depth size

        class << self
          def [](*labels)
            new(labels)
          end

          # Values coming from the database are valid by construction, so they
          # skip both the normalization and the validation
          def load(value)
            new(value.to_s.split('.'), normalize: false)
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

          # A record stands for its primary key, which is what makes a path
          # built out of other records work the same way as one built out of
          # labels
          def resolve_record(value)
            return value unless value.is_a?(::ActiveRecord::Base)

            id = value.id
            raise ArgumentError, <<~MSG.squish if id.nil?
              Unable to use #{value.class.name} as a label because its
              #{value.class.primary_key} is still empty.
            MSG

            raise ArgumentError, <<~MSG.squish if id.is_a?(::Array)
              Unable to use #{value.class.name} as a label because it has a
              composite primary key, which cannot be a single label.
            MSG

            id
          end

          # Apply the configured replacements, so callers can feed a source that
          # does not satisfy PostgreSQL's rules for a label on its own
          def sanitize(value)
            replacements = PostgreSQL.config.ltree.sanitize
            return value if replacements.blank?

            value.gsub(Regexp.union(replacements.keys), replacements)
          end
        end

        def initialize(labels = nil, normalize: true)
          super()
          concat(normalize ? normalized(labels) : Array.wrap(labels))
        end

        def to_s
          join('.')
        end

        def root?
          size <= 1
        end

        def root
          self.class.new(first, normalize: false)
        end

        # A path with a single label has no parent, and neither does an empty one
        def parent
          self.class.new(self[0..-2], normalize: false) unless root?
        end

        def /(other)
          self.class.new(to_a + self.class.new(other), normalize: false)
        end

        alias_method :+, :/

        # Same as the +@>+ operator, which includes the path itself
        def ancestor_of?(other)
          other = self.class.new(other)
          size <= other.size && other.first(size) == to_a
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
          paths = [self, *others].map { |path| self.class.new(path)[0..-2].to_a }
          result = paths.shift || []
          paths.each { |path| result = common_prefix(result, path) }
          self.class.new(result, normalize: false)
        end

        # The position where the given subpath starts, or -1 when it is not
        # present. Named apart from +index+ so that Array's own contract, of
        # returning +nil+ when the element is missing, stays intact
        def index_of(subpath, offset = 0)
          subpath = self.class.new(subpath)
          offset += size if offset.negative?
          return -1 if subpath.empty? || offset.negative?

          range = offset..(size - subpath.size)
          position = range.find { |i| self[i, subpath.size] == subpath.to_a }
          position || -1
        end

        private

          def normalized(labels)
            entries = Array.wrap(labels).flat_map { |value| split_labels(value) }
            entries.each { |label| assert_valid_label!(label) }
          end

          def split_labels(value)
            return normalized(self.class.compatible(value)) if self.class.compatible?(value)

            value = self.class.resolve_record(value)
            plain = value.is_a?(::String) || value.is_a?(::Symbol) || value.is_a?(::Numeric)
            raise ArgumentError, <<~MSG.squish unless plain
              Unable to use #{value.inspect} as part of an ltree path. A path is a
              plain sequence of labels, so it accepts neither the alternatives nor
              the quantifiers that only make sense on an lquery.
            MSG

            self.class.sanitize(value.to_s).split('.')
          end

          def assert_valid_label!(label)
            raise ArgumentError, <<~MSG.squish unless label.match?(LABEL)
              #{label.inspect} is not a valid ltree label. Labels are limited to
              letters, numbers, underscores and dashes.
            MSG
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
