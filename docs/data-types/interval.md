---
title: Interval
section: data-types
description: Reads PostgreSQL's interval data type and transforms it into Rails' ActiveSupport::Duration.
---

Reads PostgreSQL's interval data type and transforms it into Rails' `ActiveSupport::Duration`. [PostgreSQL Docs](https://www.postgresql.org/docs/9.6/static/datatype-datetime.html#DATATYPE-INTERVAL-INPUT)

## Migration

Just set the type of the column as `interval` when creating a table.
```ruby
create_table "courses" do |t|
  t.string   "title",    null: false
  t.interval "duration"
end
```

Or when you are adding a column, just use `:interval` as its type.
```ruby
add_column :courses, :duration, :interval
```

## Using it

The column is automatically identified and its value turned into `ActiveSupport::Duration`. So, any methods available on it can be used directly from your field. [RubyOnRails Doc](http://api.rubyonrails.org/classes/ActiveSupport/Duration.html)
```ruby
# Shows when you'll be finishing the course
course.duration.from_now
```

The value can be set in a few different ways:
```ruby
course.duration = 1.year                 # A new instance of ActiveSupport::Duration
course.duration = [1, 2, 3, 4, 5, 6]     # A list of values for the given order Y-M-D H:M:S
course.duration = [1, 0, 0]              # The list uses the right-most available positions, so this is H:M:S
course.duration = {days: 1, hours: 6}    # You can use complex hash notation
course.duration = 'P1Y2M3DT4H5M6S'       # It accepts ISO 8601 format, so form fields can cast to this type

course.duration = 259200
course.duration.parts.to_h == {days: 3}  # It also converts any set value to the correct separated duration
```

On your views, you can use `I18n.locale` to transform it to a readable text:
```html
<p>Course duration: <%= l @course.duration %></p>
<!-- Will print something like 'Course duration: 1 year, 2 months, and 3 days' -->
```
