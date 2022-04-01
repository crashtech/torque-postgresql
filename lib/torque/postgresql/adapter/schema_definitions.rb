# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module TableDefinition
        attr_reader :inherits

        def initialize(*args, **options)
          super

          @inherits = Array.wrap(options.delete(:inherits)).flatten.compact \
            if options.key?(:inherits)
        end
      end

      ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.include TableDefinition
    end
  end
end
