module Torque
  module PostgreSQL
    module Base
      extend ActiveSupport::Concern

      module ClassMethods
        delegate :distinct_on, to: :all
      end
    end

    ActiveRecord::Base.include Base
  end
end
