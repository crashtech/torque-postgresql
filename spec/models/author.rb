class Author < ActiveRecord::Base
  has_many :comments
end
