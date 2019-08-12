require_relative 'activity'

class ActivityPost < Activity
  belongs_to :post
end

require_relative 'activity_post/sample'
