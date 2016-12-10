class Post < ActiveRecord::Base
  has_many :authors
end
