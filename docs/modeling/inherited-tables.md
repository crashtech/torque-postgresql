---
title: Inherited Tables
section: modeling
description: This is one great feature from PostgreSQL, the ability to have a table
  with the most generic data, and then many other tables with the information necessar
---

> Tired of `polymorphic` or the infamous `type` column. Well, **NEVER MORE!!!**

This is one great feature from PostgreSQL, the ability to have a table with the most generic data, and then many other tables with the information necessary only for that specific type of the main one. Rails does allow us to do that, using the `type` attribute, but its biggest problem is that columns from different types end up getting mixed together. [PostgreSQL Docs](https://www.postgresql.org/docs/current/static/ddl-inherit.html)

This will allow you to work with inherited models, as they are separated tables but share methods, scopes, validations, and all other features from the super models.

> **Feature rich** Table inheritance is now a stable and complete part of this gem. Records come back as their real class without any opt-in, they carry the guarantees you would expect from a regular record, and the rough edges of the previous opt-in approach are gone. What you will find below is the behavior you should be able to assume, not a preview.

**CAUTION** PostgreSQL has some [**caveats**](https://www.postgresql.org/docs/9.1/static/ddl-inherit.html#DDL-INHERIT-CAVEATS) while using this resource. Most of them come down to what a child table does **not** get from its parent, which is what [Syncing features](#syncing-features) exists to solve.

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

## Syncing features {#syncing-features}

PostgreSQL only carries part of a parent's schema down to its children. Columns come across, and so do their `NOT NULL` and `DEFAULT`, and any `CHECK` constraint. Everything else stops at the parent:

| Feature | Inherited by PostgreSQL |
| --- | --- |
| Columns, `NOT NULL`, `DEFAULT` | Yes |
| `CHECK` constraints | Yes |
| Primary key | **No** |
| Indexes | **No** |
| `UNIQUE` constraints | **No** |
| `EXCLUDE` constraints | **No** |
| Foreign keys | **No** |

Indexes are the one that hurts most. A query against `activities` reads every child table, and each of those can only use the indexes it owns, so an index that exists only on the parent does nothing for the rows stored below it.

Pass `sync` when creating a table to bring all of it across at once.

```ruby
create_table "activity_books", inherits: :activities, sync: true do |t|
  t.string "isbn"
end
```

Or spread from the parent at any later point, which reaches every descendant.

```ruby
sync_inheritance_features :activities
```

The second argument narrows it to specific tables. Those are the only ones written to, so list the intermediate tables as well when you want a whole branch.

```ruby
sync_inheritance_features :activities, %i[activity_books activity_posts]
```

### Picking features

The features are `primary_key`, `indexes`, `unique_constraints`, `exclusion_constraints` and `foreign_keys`. Passing one as `false` leaves it out, and passing any of them as `true` instead makes that the whole selection.

```ruby
# Everything but the foreign keys
sync_inheritance_features :activities, foreign_keys: false

# Only the indexes
sync_inheritance_features :activities, indexes: true

# The same two forms work on create_table
create_table "activity_books", inherits: :activities, sync: { indexes: true }
```

Running it again changes nothing, so it is safe to leave in place and safe to run against a hierarchy that is already partly set up.

### How copies are named

Everything a sync creates is named `sync_inh_` followed by a short digest of where it came from and where it went, such as `sync_inh_e68e522cea`. The name is the same in every database, it can never run past the identifier limit, and it is what marks the object as a copy.

That marker is written into `schema.rb` along with the object, so it survives `db:schema:load`.

The primary key is the exception. PostgreSQL names it after the table, and there is no way to describe that name in a dump, so it carries no marker. It shows up in the dump as an option on the table instead:

```ruby
create_table "activity_books", id: false, inherits: "activities", sync: { primary_key: true }, force: :cascade do |t|
  t.string "isbn"
end
```

Everything else needs no special treatment, since Rails already dumps indexes and constraints for each table on its own.

### Removing what the parent dropped

A sync only ever adds. Pass `prune` to also drop copies whose source is gone from the parent.

```ruby
sync_inheritance_features :activities, prune: true
```

Only objects carrying the marker are ever considered, so anything you wrote by hand on a child is left alone, even an index on a column that came from the parent. Primary keys are never dropped.

This is also what a rollback does. `sync_inheritance_features` inverts into the same call with `prune` on, bringing the children back in line with the parent.

The pruning is held back until the very end of the rollback, after everything else the migration did has been undone. So this migration needs no `up` and `down` of its own: on the way down the index is removed from the parent first, and the children are then compared against the parent as it ends up rather than as it started.

```ruby
def change
  add_index :activities, :title
  sync_inheritance_features :activities
end
```

### Things a sync cannot fix

A primary key or a unique constraint on a child is enforced within that child, not across the whole hierarchy. Children do share the parent's sequence, so generated ids stay unique in practice, but nothing guarantees it for values you set yourself.

A foreign key pointing **at** the parent does not see rows stored in the children, and there is no way around it. Only the parent's own outgoing foreign keys can be copied down.

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

### Records as their real class

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

A record instantiated this way was read from the base table, so it only carries the base table's columns. Such a record is **partial** and therefore **read-only**.

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
# so its records will not be instantiated as their real class.
```

Add the `:_regclass` token to the selection to keep it:

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

A relation that replaces its source through `from` does not add the marker itself, since the `tableoid` system column belongs to the real table. The real class then survives only when the source you provide already carries the marker, and it is silently lost when it does not.

```ruby
# Real classes, because the inner relation projects the marker
Activity.from(Activity.all, :activities).to_a

# Everything comes back as Activity, and nothing warns
Activity.from('activities').to_a
Activity.from(Activity.all.select(:id, :title), :activities).to_a
```
