class Post < ActiveRecord::Base
  belongs_to :author
  belongs_to :activity

  scope :test_scope, -> { where('1=1') }
end
