module Torque
  module Postgresql
    module Model

      Base      = ActiveRecord::Base
      Connector = ActiveRecord::ConnectionAdapters::PostgreSQL

    end
  end
end

require 'torque/postgresql/model/enum'
