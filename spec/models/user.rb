class User < ActiveRecord::Base
  has_many :comments

  auxiliary_statement :last_comment do
    attributes id: :comment_id, content: :comment_content
    join id: :user_id

    query Comment.distinct_on(:user_id).order(:user_id, id: :desc)
  end
end
