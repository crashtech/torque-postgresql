class Author < ActiveRecord::Base
  has_many :activities, dependent: :destroy
  has_many :posts
end
