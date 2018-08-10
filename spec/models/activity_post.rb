class ActivityPost < Activity
  self.table_name = 'activity_posters'

  belongs_to :post
end
