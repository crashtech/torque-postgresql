module Torque
  module PostgreSQL
    class AuxiliaryStatement
      class Settings < Collector.new(:attributes, :join, :join_type, :query)

        attr_reader :source
        alias cte source

        delegate :base, :base_table, :table, :table_name, to: :@source

        def initialize(source)
          @source = source
        end

        def query_table
          raise StandardError, 'The query is not defined yet' if query.nil?
          query.arel_table
        end

      end
    end
  end
end
