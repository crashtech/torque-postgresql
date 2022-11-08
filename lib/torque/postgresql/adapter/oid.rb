require_relative 'oid/box'
require_relative 'oid/circle'
require_relative 'oid/enum'
require_relative 'oid/enum_set'
require_relative 'oid/interval'
require_relative 'oid/line'
require_relative 'oid/range'
require_relative 'oid/segment'
require_relative 'oid/struct'

module Torque
  module PostgreSQL
    module Adapter
      module OID
      end

      ActiveRecord::Type.register(:box,      OID::Box,      adapter: :postgresql)
      ActiveRecord::Type.register(:circle,   OID::Circle,   adapter: :postgresql)
      ActiveRecord::Type.register(:enum,     OID::Enum,     adapter: :postgresql)
      ActiveRecord::Type.register(:enum_set, OID::EnumSet,  adapter: :postgresql)
      ActiveRecord::Type.register(:line,     OID::Line,     adapter: :postgresql)
      ActiveRecord::Type.register(:segment,  OID::Segment,  adapter: :postgresql)
    end
  end
end
