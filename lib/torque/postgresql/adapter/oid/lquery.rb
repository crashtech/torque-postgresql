# frozen_string_literal: true

require_relative 'ltree'

module Torque
  module PostgreSQL
    module Adapter
      module OID
        # Same as a path, but the items are the pure parts of a pattern: +:any+
        # for a star, a Range for a quantified star and an Array for a group of
        # alternatives. Everything else is a label, written as it appears in SQL
        class Lquery < Ltree
          STAR = /\A\*\{(?<min>\d+)?(?<comma>,)?(?<max>\d+)?\}\z/

          def type
            :lquery
          end

          private

            def value_class
              LQuery
            end

            def items_of(entry, sanitize)
              case entry
              when ::Symbol then entry == :any ? [:any] : super
              when ::Range then [entry]
              when ::Array then [entry.flat_map { |item| items_of(item, sanitize) }]
              else super
              end
            end

            def compile(item)
              case item
              when ::Symbol then item == :any ? '*' : item.to_s
              when ::Range then quantifier(item)
              when ::Array then item.map { |entry| compile(entry) }.join('|')
              else item.to_s
              end
            end

            def quantifier(range)
              min = range.begin
              max = range.end
              max -= 1 if max && range.exclude_end?

              return '*' if min.nil? && max.nil?
              return "*{#{min}}" if min == max

              "*{#{min},#{max}}"
            end

            def parse(text)
              return :any if text == '*'
              return text.split('|') if text.include?('|') && !text.match?(/[!{]/)

              match = text.match(STAR)
              return text if match.nil?

              min = match[:min]&.to_i
              max = match[:comma] ? match[:max]&.to_i : min
              min..max
            end

        end
      end
    end
  end
end
