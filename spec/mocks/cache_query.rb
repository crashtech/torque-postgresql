module Mocks
  module CacheQuery
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

    def get_query_with_binds(&block)
      result = nil

      original_method = ActiveRecord::Base.connection.method(:raw_execute)
      original_method.receiver.define_singleton_method(:raw_execute) do |*args, **xargs, &block|
        result ||= [args.first, args.third]
        super(*args, **xargs, &block)
      end

      block.call
      original_method.receiver.define_singleton_method(:raw_execute, &original_method.to_proc)

      result
    end
  end
end
