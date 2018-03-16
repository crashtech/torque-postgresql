module Torque
  module PostgreSQL
    class AuxiliaryStatement
      class Settings < Collector.new(:attributes, :join, :join_type, :query, :requires,
                                     :polymorphic)

        attr_reader :source
        alias cte source

        delegate :base, :base_name, :base_table, :table, :table_name, to: :@source
        delegate :relation_query?, to: Torque::PostgreSQL::AuxiliaryStatement

        def initialize(source)
          @source = source
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
        # - A string or a proc that requires the table name as first argument
        def query(value = nil, command = nil)
          return @query if value.nil?
          return @query = value if relation_query?(value)

          valid_type = command.respond_to?(:call) || command.is_a?(String)
          raise ArgumentError, <<-MSG.strip.gsub(/\n +/, ' ') if command.nil?
            To use proc or string as query, you need to provide the table name
            as the first argument
          MSG
          raise ArgumentError, <<-MSG.strip.gsub(/\n +/, ' ') unless valid_type
            Only relation, string and proc are valid object types for query,
            #{command.inspect} given.
          MSG

          @query = command
          @query_table = Arel::Table.new(value)
        end

      end
    end
  end
end
