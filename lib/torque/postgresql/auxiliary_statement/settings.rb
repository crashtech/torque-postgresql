# frozen_string_literal: true

module Torque
  module PostgreSQL
    class AuxiliaryStatement
      class Settings < Collector.new(:attributes, :join, :join_type, :query, :requires,
          :polymorphic, :through, :all, :connect)

        attr_reader :base, :source
        alias_method :select, :attributes
        alias_method :cte, :source

        delegate :relation_query?, to: Torque::PostgreSQL::AuxiliaryStatement
        delegate :table, :table_name, to: :@source
        delegate :sql, to: ::Arel

        def initialize(base, source, recursive = false)
          @base = base
          @source = source
          @recursive = recursive
        end

        def base_name
          @base.name
        end

        def base_table
          @base.arel_table
        end

        def recursive?
          @recursive
        end

        def depth?
          defined?(@with_depth)
        end

        def path?
          defined?(@with_path)
        end

        # Add an attribute to the result showing the depth of each iteration
        def with_depth(name = 'depth')
          @with_depth = name if recursive?
        end

        # Add an attribute to the result showing the path of each record
        def with_path(name = 'path', source = nil)
          @with_path = [name, source] if recursive?
        end

        # Add both depth and path to the result
        def with_depth_and_path
          with_depth && with_path
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

        # There are three ways of setting the query:
        # - A simple relation based on a Model
        # - A Arel-based select manager
        # - A string or a proc that requires the table name as first argument
        def query(value = nil, command = nil)
          return @query if value.nil?

          @query, @query_table = query_parts(value, command)
        end

        # Same as query, but for the second part of the union for recursive cte
        def sub_query(value = nil, command = nil)
          return unless recursive?
          return @sub_query if value.nil?

          @sub_query, @sub_query_table = query_parts(value, command)
        end

        private

          # Get the query and table from the params
          def query_parts(value, command = nil)
            return [value] if relation_query?(value)
            return [value, value.source.left.name] if value.is_a?(::Arel::SelectManager)

            valid_type = command.respond_to?(:call) || command.is_a?(String)

            raise ArgumentError, <<-MSG.squish if command.nil?
              To use proc or string as query, you need to provide the table name
              as the first argument
            MSG

            raise ArgumentError, <<-MSG.squish unless valid_type
              Only relation, string and proc are valid object types for query,
              #{command.inspect} given.
            MSG

            [command, ::Arel::Table.new(value)]
          end

      end
    end
  end
end
