# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module OID
        module Array
          def force_equality?(value)
            PostgreSQL.config.predicate_builder.handle_array_attributes ? false : super
          end
        end

        ::ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array.prepend(Array)
      end
    end
  end
end
