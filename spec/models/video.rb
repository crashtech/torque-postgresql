class Video < ActiveRecord::Base
  self.inheritance_column = 'kkkk'
  belongs_to_many :tags
end
