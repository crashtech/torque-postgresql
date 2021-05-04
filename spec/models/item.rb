class Item < ActiveRecord::Base
  belongs_to_many :tags
end
