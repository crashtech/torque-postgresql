# frozen_string_literal: true

require_relative 'builder/enum'
require_relative 'builder/period'
require_relative 'builder/full_text_search'

module Torque
  module PostgreSQL
    module Attributes
      module Builder
        def self.include_on(klass, method_name, builder_klass, **extra, &block)
          klass.define_singleton_method(method_name) do |*args, **options|
            return unless table_exists?

            args.each do |attribute|
              # Generate methods on self class
              builder = builder_klass.new(self, attribute, extra.merge(options))
              builder.conflicting?
              builder.build

              # Additional settings for the builder
              instance_exec(builder, &block) if block.present?
            rescue Interrupt
              # Not able to build the attribute, maybe pending migrations
            end
          end
        end

        def self.search_vector_options(columns:, language: nil, stored: true, **options)
          weights = to_search_weights(columns)
          operation = to_search_vector_operation(language, weights)

          options[:index] = {
            using: PostgreSQL.config.full_text_search.default_index_type,
          } if options[:index] == true

          options.merge(type: :tsvector, as: operation, stored: stored)
        end

        def self.to_search_weights(columns)
          if !columns.is_a?(Hash)
            extras = columns.size > 3 ? columns.size - 3 : 0
            weights = %w[A B C] + (['D'] * extras)
            columns = Array.wrap(columns).zip(weights).to_h
          end

          columns.transform_keys(&:to_s)
        end

        def self.to_search_vector_operation(language, weights)
          language ||= PostgreSQL.config.full_text_search.default_language
          language = ::Arel.sql(language.is_a?(Symbol) ? language.to_s : "'#{language}'")
          simple = weights.size == 1

          empty_string = ::Arel.sql("''")
          fn = ::Arel::Nodes::NamedFunction

          weights.map do |column, weight|
            column = ::Arel.sql(column.to_s)
            weight = ::Arel.sql("'#{weight}'")

            op = fn.new('COALESCE', [column, empty_string])
            op = fn.new('TO_TSVECTOR', [language, op])
            op = fn.new('SETWEIGHT', [op, weight]) unless simple
            op.to_sql
          end.join(' || ')
        end
      end
    end
  end
end
