class Tag < ActiveRecord::Base
  has_many :videos, array: true
end
