class User < ActiveRecord::Base
  has_many :comments

  auxiliary_statement :last_comment do |cte|
    cte.query Comment.distinct_on(:user_id).order(:user_id, id: :desc)
    cte.attributes id: :comment_id, content: :comment_content
  end
end
