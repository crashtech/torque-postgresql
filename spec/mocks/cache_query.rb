module Mocks
  module CacheQuery
    if Torque::PostgreSQL::AR720
      def get_last_executed_query(&block)
        cache = ActiveRecord::Base.connection.query_cache
        cache.instance_variable_set(:@enabled, true)

        map = cache.instance_variable_get(:@map)

        block.call
        result = map.keys.first

        cache.instance_variable_set(:@enabled, false)
        map.delete(result)

        result
      end
    else
      def get_last_executed_query(&block)
        conn = ActiveRecord::Base.connection
        conn.instance_variable_set(:@query_cache_enabled, true)

        block.call
        result = conn.query_cache.keys.first

        conn.instance_variable_set(:@query_cache_enabled, false)
        conn.instance_variable_get(:@query_cache).delete(result)

        result
      end
    end
  end
end
