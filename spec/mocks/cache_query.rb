module Mocks
  module CacheQuery
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
