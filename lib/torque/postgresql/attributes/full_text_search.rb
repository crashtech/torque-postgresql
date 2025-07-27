# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Attributes
      # For now, full text search doesn't have it's own class
      module FullTextSearch
        class << self
          # Provide a method on the given class to setup which full text search
          # columns will be manually initialized
          def include_on(klass, method_name = nil)
            method_name ||= PostgreSQL.config.full_text_search.base_method
            Builder.include_on(klass, method_name, Builder::FullTextSearch)
          end
        end
      end
    end
  end
end
