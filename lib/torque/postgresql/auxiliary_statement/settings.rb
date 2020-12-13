# frozen_string_literal: true

module Torque
  module PostgreSQL
    class AuxiliaryStatement
      class Settings < Collector.new(:attributes, :join, :join_type, :query, :requires,
          :polymorphic, :through)

        attr_reader :base, :source
        alias_method :select, :attributes
        alias_method :cte, :source

        delegate :relation_query?, to: Torque::PostgreSQL::AuxiliaryStatement
        delegate :table, :table_name, to: :@source
        delegate :sql, to: ::Arel

        def initialize(base, source)
          @base = base
          @source = source
        end

        def base_name
          @base.name
        end

        def base_table
          @base.arel_table
        end

        # Get the arel version of the table set on the query
        def query_table
          raise StandardError, 'The query is not defined yet' if query.nil?
          return query.arel_table if relation_query?(query)
          @query_table
        end

        # Grant an easy access to arel table columns
        def col(name)
          query_table[name.to_s]
        end

        alias column col

        # There are two ways of setting the query:
        # - A simple relation based on a Model
        # - A Arel-based select manager
        # - A string or a proc that requires the table name as first argument
        def query(value = nil, command = nil)
          return @query if value.nil?
          return @query = value if relation_query?(value)

          if value.is_a?(::Arel::SelectManager)
            @query = value
            @query_table = value.source.left.name
            return
          end

          valid_type = command.respond_to?(:call) || command.is_a?(String)

          raise ArgumentError, <<-MSG.squish if command.nil?
            To use proc or string as query, you need to provide the table name
            as the first argument
          MSG

          raise ArgumentError, <<-MSG.squish unless valid_type
            Only relation, string and proc are valid object types for query,
            #{command.inspect} given.
          MSG

          @query = command
          @query_table = ::Arel::Table.new(value)
        end

      end
    end
  end
end
