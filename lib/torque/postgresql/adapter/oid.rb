require_relative 'oid/array'
require_relative 'oid/enum'
require_relative 'oid/interval'

module Torque
  module PostgreSQL
    module Adapter
      module OID
      end

      ActiveRecord::Type.register(:enum, OID::Enum, adapter: :postgresql)
      ActiveRecord::Type.register(:interval, OID::Interval, adapter: :postgresql)
    end
  end
end
