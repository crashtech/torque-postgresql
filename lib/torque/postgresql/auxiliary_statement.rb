module Torque
  module PostgreSQL
    class AuxiliaryStatement

      # Base struc to fill out the statement settings
      Settings = Collector.new(:attributes, :join, :join_type, :query)

    end
  end
end
