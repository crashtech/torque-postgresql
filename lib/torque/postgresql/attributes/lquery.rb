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
        LEVEL = /\A(?<not>!)?(?<variants>.*?)(?:\{(?<min>\d*)(?<comma>,)?(?<max>\d*)\})?\z/
        VARIANT = /\A(?<name>.*?)(?<modifiers>[*@%]*)\z/

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

        def pattern?
          items.any? { |item| !item.is_a?(::String) || item.match?(MARKERS) }
        end

        def pattern
          @pattern ||= compile
        end

        def match?(path)
          path = LTree.new(path) unless path.is_a?(LTree)
          pattern.match?(path.to_s)
        end

        def =~(path)
          path = LTree.new(path) unless path.is_a?(LTree)
          pattern =~ path.to_s
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

          def compile
            levels = to_s.split('.', -1).map { |level| compile_level(level) }
            Regexp.new("\\A#{levels.join}\\z")
          end

          def compile_level(text)
            match = text.match(LEVEL)
            variants = match[:variants]
            label = variants == '*' ? '[^.]+' : compile_variants(variants.split('|'))
            label = "(?!#{label}(?:\\.|\\z))[^.]+" if match[:not]
            "(?:(?:\\A|\\.)#{label})#{quantifier(match)}"
          end

          def compile_variants(variants)
            sources = variants.map { |variant| compile_variant(variant) }
            "(?:#{sources.join('|')})"
          end

          def compile_variant(text)
            match = text.match(VARIANT)
            modifiers = match[:modifiers]
            prefix = modifiers.include?('*')
            name = match[:name]

            source = modifiers.include?('%') ? words(name, prefix) : label(name, prefix)
            modifiers.include?('@') ? "(?i:#{source})" : source
          end

          def label(name, prefix)
            "#{Regexp.escape(name)}#{'[^.]*' if prefix}"
          end

          def words(name, prefix)
            lookaheads = name.split('_').reject(&:empty?).map do |word|
              "(?=(?:[^.]*_)?#{Regexp.escape(word)}#{'[^._]*' if prefix}(?:[_.]|\\z))"
            end

            "#{lookaheads.join}[^.]+"
          end

          def quantifier(match)
            return match[:variants] == '*' ? '*' : '' if match[:min].nil?

            min = match[:min].presence || 0
            max = match[:comma] ? match[:max] : min
            "{#{min},#{max}}"
          end
      end
    end

    LQuery = Attributes::LQuery
  end
end
