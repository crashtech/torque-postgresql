---
title: Inherited Tables
section: models
description: This is one great feature from PostgreSQL, the ability to have a table
  with the most generic data, and then many other tables with the information necessar
---

> Tired of `polymorphic` or the infamous `type` column. Well, **NEVER MORE!!!**

This is one great feature from PostgreSQL, the ability to have a table with the most generic data, and then many other tables with the information necessary only for that specific type of the main one. Rails does allow us to do that, using the `type` attribute, but its biggest problem is that columns from different types end up getting mixed together. [PostgreSQL Docs](https://www.postgresql.org/docs/current/static/ddl-inherit.html)

This will allow you to work with inherited models, as they are separated tables but share methods, scopes, validations, and all other features from the super models.

**CAUTION** PostgreSQL has some [**caveats**](https://www.postgresql.org/docs/9.1/static/ddl-inherit.html#DDL-INHERIT-CAVEATS) while using this resource. They will be addressed in later versions of this gem.

## Migration

First, you have to create a base table. Then, create as many tables as wanted, specifying the `:inherited` key.

```ruby
create_table "activities" do |t|
  t.string "title"
end

create_table "activity_books", inherits: :activities do |t|
  t.belongs_to "author_id"
  t.datetime   "published_at"
end

create_table "activity_posts", inherits: :activities do |t|
  t.belongs_to "post_id"
  t.datetime   "published_at"
end
```

## Models

To have your models work correctly and take full advantage of this feature, the same way tables are inherited, the models need to be inherited as well.

```ruby
# models/activity.rb
class Activity < ApplicationRecord
end

# models/activity_book.rb
class ActivityBook < Activity
end

# models/activity_post.rb
class ActivityPost < Activity
end
```

### Table name to Model name

Since the data that indicates the record type is a table name, this process relies on Rails' standard translation from class name to table name. But this is tricky, because `activity_posts` can either be `ActivityPost` or `Activity::Post` (or even another model using `self.table_name = "activity_posts"`). This gem tries its best to translate the table name to a model name, checking all the possibilities, so you might not face issues. **But**, you can always help it, and make the process more accurate or even faster.

Please check the [Configuration Page]({{ site.baseurl }}/getting-started/configuring/) to see the options for improving this operation.

The most important setting is the [`irregular_models`]({{ site.baseurl }}/getting-started/configuring/#irregular_models) option, which can both help describe the correct relationship between a table name and a model name and improve performance by avoiding the default behavior of searching for the model based on the table name. Although the table name once associated with a model name is cached, please note this when setting irregular names.

```ruby
Torque::PostgreSQL.configure do |c|
  c.irregular_models = {
    'my_awesome_table_name' => 'SimpleModel'
  }
end
```

### Single record

Any already loaded record can be cast to its original model using `cast_record` method. **Be careful** that this method relies on a `primary_key` to be correctly cast.

```ruby
ActivityPost.create(title: 'Post 1')
Activity.first                             # #<Activity id: 1, title: "Post 1" ...
Activity.first.cast_record                 # #<ActivityPost id: 1, title: "Post 1" ...
```

### Multiple records

You can also inform the relation to automatically cast all the returned records to their original model using `cast_records` while querying.

```ruby
Activity.create(title: 'Activity 1')
ActivityPost.create(title: 'Post 1')
ActivityBook.create(title: 'Book 1')

list = Activity.all.cast_records.load.to_a
list.first                                 # #<Activity id: 1, title: "Activity 1" ...
list.second                                # #<ActivityPost id: 2, title: "Post 1" ...
list.third                                 # #<ActivityBook id: 3, title: "Book 1" ...
```

The `cast_records` provides other filters like specifying which classes should be cast and if they should be filtered while querying.

```ruby
# No filter applied
list = Activity.all.cast_records(ActivityPost).load.to_a
list.first                                 # #<Activity id: 1, title: "Activity 1" ...
list.second                                # #<ActivityPost id: 2, title: "Post 1" ...
list.third                                 # #<Activity id: 3, title: "Book 1" ...

# With filter applied
list = Activity.all.cast_records(ActivityPost, filter: true).load.to_a
list.first                                 # #<Activity id: 1, title: "Activity 1" ...
list.second                                # #<ActivityPost id: 2, title: "Post 1" ...
list.third                                 # nil
```

### Non confliting records

With this feature, another method was introduced. The `itself_only` option only allows queries on the base table, excluding any inherited records. It uses the `FROM ONLY` SQL clause, so it's very efficient.

```ruby
list = Activity.itself_only.load.to_a
list.first                                 # #<Activity id: 1, title: "Activity 1" ...
list.second                                # nil
list.third                                 # nil
```

### ~~Returning the records' type~~

~~In order to perform any query with correct performance and maintainability, this feature uses [Auxiliary Statements]({{ site.baseurl }}/querying/auxiliary-statements/) and [Dynamic Attributes]({{ site.baseurl }}/models/dynamic-attributes/).~~

> **Deprecated** This is being replaced by a cast operation that translates the tableoid into its table name (AKA regclass), as in `"activities"."tableoid"::regclass`. This improvement removes the necessity of an auxiliary statement and an extra join in queries. The support for getting the actual table name of a record will change in the next versions.

The `_record_class` method (which can be renamed using the [`inheritance.record_class_column_name`]({{ site.baseurl }}/getting-started/configuring/#inheritance.record_class_column_name) setting) is used both as an Auxiliary Statement and a Dynamic Attribute to get the type of the records. While it's a great example of these provided features, you can always take advantage of this to get the type of the record.

```ruby
list = Activity.all.with(:_record_class).load.to_a
list.first._record_class                   # "activities"
list.second._record_class                  # "activity_posts"
list.third._record_class                   # "activity_books"
```
