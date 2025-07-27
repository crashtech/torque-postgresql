# frozen_string_literal: true

module Torque
  module PostgreSQL
    module PredicateBuilder
      class EnumeratorLazyHandler < ::ActiveRecord::PredicateBuilder::ArrayHandler
        Timeout = Class.new(::Timeout::Error)

        def call(attribute, value)
          with_timeout do
            super(attribute, limit.nil? ? value.force : value.first(limit))
          end
        end

        private

          def with_timeout
            return yield if timeout.nil?

            begin
              ::Timeout.timeout(timeout) { yield }
            rescue ::Timeout::Error
              raise Timeout, "Lazy predicate builder timed out after #{timeout} seconds"
            end
          end

          def timeout
            PostgreSQL.config.predicate_builder.lazy_timeout
          end

          def limit
            PostgreSQL.config.predicate_builder.lazy_limit
          end
      end
    end
  end
end
