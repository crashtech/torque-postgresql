---
title: Inherited Tables
section: models
description: This is one great feature from PostgreSQL, the ability to have a table
  with the most generic data, and then many other tables with the information necessar
---

> Tired of `polymorphic` or the infamous `type` column. Well, **NEVER MORE!!!**

This is one great feature from PostgreSQL, the ability to have a table with the most generic data, and then many other tables with the information necessary only for that specific type of the main one. Rails does allow us to do that, using the `type` attribute, but its biggest problem is that columns from different types end up getting mixed together. [PostgreSQL Docs](https://www.postgresql.org/docs/current/static/ddl-inherit.html)

This will allow you to work with inherited models, as they are separated tables but share methods, scopes, validations, and all other features from the super models.

> **Feature rich** Table inheritance is now a stable and complete part of this gem. Records come back as their real class without any opt-in, they carry the guarantees you would expect from a regular record, and the rough edges of the previous opt-in approach are gone. What you will find below is the behavior you should be able to assume, not a preview.

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

### Casting records

Querying a model whose table has inherited tables returns every record already as its real class. There is nothing to opt into.

```ruby
Activity.create(title: 'Activity 1')
ActivityPost.create(title: 'Post 1', published_at: Time.current)
ActivityBook.create(title: 'Book 1', published_at: Time.current)

list = Activity.order(:id).load.to_a
list.first                                 # #<Activity id: 1, title: "Activity 1" ...
list.second                                # #<ActivityPost id: 2, title: "Post 1" ...
list.third                                 # #<ActivityBook id: 3, title: "Book 1" ...
```

This works because the query projects `"activities"."tableoid"::regclass` as the `_record_class` column, and each row is instantiated with the model that owns the table it came from.

The same applies when the records arrive through an association, using either `includes` or `eager_load`, and without any additional query.

```ruby
Author.eager_load(:activities).first.activities.map(&:class)
# [Activity, ActivityPost, ActivityBook]
```

If the table name cannot be translated into a model, the query raises a `Torque::PostgreSQL::InheritanceError` telling you to describe it through the [`irregular_models`]({{ site.baseurl }}/getting-started/configuring/#irregular_models) setting.

### Partial and read-only records

A casted record was read from the base table, so it only carries the base table's columns. Such a record is **partial** and therefore **read-only**.

```ruby
book = Activity.order(:id).third
book.partial_record?                       # true
book.readonly?                             # true

book.published_at                          # raises ActiveModel::MissingAttributeError
book.update!(title: 'Changed')             # raises ActiveRecord::ReadOnlyRecord
```

Two operations still work as usual, because neither needs the missing columns:

```ruby
book.reload                                # Queries activity_books, returns a complete and writable record
book.destroy                               # Deletes the row from both tables
```

> **Note** A record whose own table adds no columns of its own is complete by definition, so it is never marked as partial.

> **Heads up** This applies to records reached through an association too, however they were loaded. `author.activities`, `includes(:activities)`, `preload(:activities)` and `eager_load(:activities)` all return partial and read-only records, so writing to one raises `ActiveRecord::ReadOnlyRecord`. If you intend to change them, load them with `expand_records`, as described below. This is the most likely thing to break when upgrading, since associations previously handed back plain writable records of the base model.

### Expanding records

Use `expand_records` when you want the inherited columns loaded, so the records come out complete and writable.

```ruby
list = Activity.expand_records.order(:id).load.to_a
list.third.published_at                    # The value stored on activity_books
list.third.partial_record?                 # false
list.third.readonly?                       # false
```

By default it expands every dependent that adds columns, running one additional query per inherited table. You can name the types explicitly, and ask for a single query using outer joins instead:

```ruby
# One extra query, only for ActivityBook
Activity.expand_records(ActivityBook)

# A single query, using LEFT OUTER JOIN
Activity.expand_records(ActivityBook, eager_load: true)
```

The `filter` option additionally restricts the result to the given types:

```ruby
list = Activity.expand_records(ActivityPost, filter: true).load.to_a
list.map(&:class)                          # [ActivityPost]
```

To expand the records of an association, merge the expansion into the query that loads them:

```ruby
author = Author.includes(:activities).merge(Activity.expand_records).first
author.activities.first.readonly?          # false
```

### Selecting specific columns

An explicit `select` owns the projection, which means the `_record_class` marker is no longer added and the records come back as the base model. When that happens, a warning is printed:

```ruby
Activity.select(:id, :title).to_a
# Activity was queried with an explicit select that omits :_regclass,
# so its records will not be casted to their real class.
```

Add the `:_regclass` token to the selection to keep the casting:

```ruby
Activity.select(:_regclass, :id, :title).to_a
# SELECT "activities"."tableoid"::regclass AS _record_class, "activities"."id", "activities"."title"
```

### Non conflicting records

With this feature, another method was introduced. The `itself_only` option only allows queries on the base table, excluding any inherited records. It uses the `FROM ONLY` SQL clause, so it's very efficient.

```ruby
list = Activity.itself_only.load.to_a
list.first                                 # #<Activity id: 1, title: "Activity 1" ...
list.second                                # nil
list.third                                 # nil
```

### Returning the records' type

The type of a record is now simply its class, so there is no separate attribute to read.

```ruby
list = Activity.order(:id).load.to_a
list.first.class.table_name                # "activities"
list.second.class.table_name               # "activity_posts"
list.third.class.table_name                # "activity_books"
```

> **Note** The `_record_class` name, which can be changed through the [`inheritance.record_class_column_name`]({{ site.baseurl }}/getting-started/configuring/#inheritance.record_class_column_name) setting, is only the alias of the marker column in the generated SQL. It is consumed while instantiating each record and is not kept as an attribute, which is why `record._record_class` does not exist.

### Things to be aware of

`itself_only` and `expand_records` describe opposite intentions, so combining them raises a `Torque::PostgreSQL::InheritanceError`. Reading from `ONLY` a table never returns the inherited records that `expand_records` exists to complete.

A relation that replaces its source through `from` does not add the marker itself, since the `tableoid` system column belongs to the real table. Casting then survives only when the source you provide already carries the marker, and it is silently lost when it does not.

```ruby
# Casts, because the inner relation projects the marker
Activity.from(Activity.all, :activities).to_a

# Does not cast, and does not warn
Activity.from('activities').to_a
Activity.from(Activity.all.select(:id, :title), :activities).to_a
```
