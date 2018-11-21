class Post < ActiveRecord::Base
  belongs_to :author

  scope :test_scope, -> { where('1=1') }
end
