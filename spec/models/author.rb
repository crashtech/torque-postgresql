class Author < ActiveRecord::Base
  has_many :activities, -> { cast_records }
end
