# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Attributes
      # A pattern that matches label paths, as described by the +lquery+ data
      # type. It is only ever built from Ruby and never parsed back from its
      # text form, so each entry of the given list becomes one item
      class LQuery
        MARKERS = /[*|!{}@%]/
        QUANTIFIER = /\{(?:\d+|\d*,\d*)\}/
        LABEL = /[[:alnum:]_-]+/
        ALTERNATIVE = /#{LABEL}[@*%]{0,3}/
        ITEM = /\A!?#{ALTERNATIVE}(?:\|#{ALTERNATIVE})*#{QUANTIFIER}?\z/
        STAR_ITEM = /\A\*#{QUANTIFIER}?\z/

        class << self
          def [](*items)
            new(items)
          end

          # Values coming from the database are valid by construction
          def load(value)
            new(value, normalize: false)
          end

          # Whether the given value asks for a pattern instead of a plain path,
          # which is what makes a condition use +~+ instead of +=+
          def marker?(value)
            Array.wrap(value).any? { |item| item_marker?(item) }
          end

          private

            def item_marker?(item)
              return marker?(LTree.compatible(item)) if LTree.compatible?(item)

              case item
              when ::Symbol then item == :any
              when ::Range, ::Array, LQuery then true
              when ::String then item.match?(MARKERS)
              else false
              end
            end
        end

        attr_reader :items

        def initialize(items, normalize: true)
          items = normalize ? expand(items) : Array.wrap(items)
          @items = normalize ? items.map { |item| compile(item) } : items.map(&:to_s)
        end

        def to_s
          items.join('.')
        end

        def ==(other)
          other.is_a?(LQuery) && to_s == other.to_s
        end
        alias eql? ==

        def hash
          to_s.hash
        end

        private

          # An object that describes itself as a path contributes every one of
          # its labels as an item, rather than a single one
          def expand(value)
            return expand(LTree.compatible(value)) if LTree.compatible?(value)

            value = value.split('.') if value.is_a?(::String)
            Array.wrap(value).flat_map { |item| expand_item(item) }
          end

          def expand_item(item)
            return expand(LTree.compatible(item)) if LTree.compatible?(item)

            [item]
          end

          def compile(item)
            case item
            when ::Range then compile_range(item)
            when ::Array then compile_alternatives(item)
            when ::Symbol then item == :any ? '*' : compile_item(item)
            when ::String, ::Numeric, ::ActiveRecord::Base then compile_item(item)
            else
              raise ArgumentError, <<~MSG.squish
                Unable to use #{item.inspect} as an lquery item. Items are labels,
                a Range for a quantified star, or an Array of alternatives.
              MSG
            end
          end

          # A Range is always a quantifier over the star, since a star on its own
          # already means any number of labels
          def compile_range(range)
            min = range.begin
            max = range.end
            max -= 1 if max && range.exclude_end?

            invalid = min&.negative? || max&.negative? || (min && max && max < min)
            raise ArgumentError, <<~MSG.squish if invalid
              #{range.inspect} is not a valid quantifier for an lquery star.
            MSG

            return '*' if min.nil? && max.nil?
            return "*{#{min}}" if min == max
            return "*{#{min},}" if max.nil?
            return "*{,#{max}}" if min.nil?
            "*{#{min},#{max}}"
          end

          def compile_alternatives(list)
            raise ArgumentError, <<~MSG.squish if list.empty?
              An lquery alternation needs at least one label.
            MSG

            alternatives = list.map { |entry| compile_alternative(entry) }
            alternatives.join('|')
          end

          def compile_alternative(entry)
            alternative = sanitize_labels(assert_plain!(entry))

            raise ArgumentError, <<~MSG.squish unless alternative.match?(/\A#{ALTERNATIVE}\z/)
              #{entry.inspect} is not a valid lquery alternative. Alternatives are
              single labels, optionally followed by the #{'@*%'.inspect} modifiers.
            MSG

            alternative
          end

          def compile_item(entry)
            text = assert_plain!(entry)
            return text if text.match?(STAR_ITEM)

            head, quantifier = split_quantifier(text)
            item = sanitize_labels(head) + quantifier

            raise ArgumentError, <<~MSG.squish unless item.match?(ITEM)
              #{entry.inspect} is not a valid lquery item. An item is a label with
              the optional #{'@*%'.inspect} modifiers, optionally negated with "!",
              alternated with "|" and quantified with "{n,m}".
            MSG

            item
          end

          def assert_plain!(entry)
            entry = LTree.resolve_record(entry)
            plain = entry.is_a?(::String) || entry.is_a?(::Symbol) || entry.is_a?(::Numeric)
            raise ArgumentError, <<~MSG.squish unless plain
              Unable to use #{entry.inspect} as part of an lquery item.
            MSG

            entry.to_s
          end

          # Only the labels are normalized, so that a replacement never rewrites
          # the structure of the pattern nor the digits of a quantifier
          def sanitize_labels(text)
            text.gsub(LABEL) { |label| LTree.sanitize(label) }
          end

          def split_quantifier(text)
            match = text.match(/#{QUANTIFIER}\z/)
            return [text, ''] if match.nil?

            [match.pre_match, match[0]]
          end
      end
    end

    LQuery = Attributes::LQuery
  end
end
