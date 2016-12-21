require_relative 'oid/array'
require_relative 'oid/composite'
require_relative 'oid/interval'

module Torque
  module PostgreSQL
    module Adapter
      module OID
      end

      ActiveRecord::Type.register(:interval, OID::Interval, adapter: :postgresql)
    end
  end
end
