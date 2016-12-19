module Torque
  module PostgreSQL
    module Base

      delegate :distinct_on, to: :all

    end

    ActiveRecord::Base.send :extend, Base
  end
end
