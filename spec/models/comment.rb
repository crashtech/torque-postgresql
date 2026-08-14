class Comment < ActiveRecord::Base
  belongs_to :user
  belongs_to :commentable, polymorphic: true, foreign_key: :video_id,
    foreign_type: :kind, optional: true
end
