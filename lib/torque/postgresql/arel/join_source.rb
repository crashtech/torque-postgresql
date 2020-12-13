# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Arel
      module JoinSource
        attr_accessor :only

        def only?
          only === true
        end
      end

      ::Arel::Nodes::JoinSource.include JoinSource
    end
  end
end
