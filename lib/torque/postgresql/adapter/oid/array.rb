module Torque
  module PostgreSQL
    module Adapter
      module OID
        module Array

          def initialize(subtype, delimiter = ',')
            super
            @pg_encoder = Coder
            @pg_decoder = Coder
          end

        end

        ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array.prepend Array
      end
    end
  end
end
