require_relative 'oid/array'
require_relative 'oid/range'

module Torque
  module PostgreSQL
    module Adapter
      module OID
        def self.unwrap(type)
          type = type.__getobj__ while type.is_a?(Delegator)
          type
        end
      end
    end
  end
end
