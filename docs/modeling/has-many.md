---
title: Has Many
section: modeling
description: Has many connected through an array.
---

> Finally my database won't have those pointless join tables. This is one of my most-wanted features.

Has many connected through an array. PostgreSQL allows us to use arrays, Rails also allows us to use arrays, but we have never been able to use them on associations. Well, honestly it was a bit hard to develop this feature, but the magic it can do is worth it. [PostgreSQL Docs](https://www.postgresql.org/docs/9.6/arrays.html)

The idea is simple, one table stores all the ids and the other one says that `has many` records on that table because its record ids exist in the column of the array. Like: `Tag has many Videos connected through an array`.

## Migration

Unlike the usual `has_many`, the class that invokes it does not hold the foreign key. It is the foreign table that stores them.

```ruby
create_table "tags" do |t|
  t.string "name"
end

# `references` with array: true is not available; declare the array column directly
create_table "videos" do |t|
  t.bigint "tag_ids", array: true
  t.string "title"
end
```

## Model

Now go to your model and simply activate the feature in much the same way as before, with just the extra `array: true` option.

```ruby
# models/tag.rb
class Tag < ApplicationRecord
  has_many :videos, array: true
end
```

All the original features from the `has_many` association are available, preloading included. You can check the methods on the [Associations Docs](https://api.rubyonrails.org/classes/ActiveRecord/Associations/ClassMethods.html) from Rails.

**One important notice** is that polymorphism is not allowed for array-like associations, because the tuples can't be guaranteed every time.

There are no extra methods provided, only some for metaprogramming if necessary.
