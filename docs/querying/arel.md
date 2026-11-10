---
title: Arel
section: querying
description: Additional Arel features.
---

Additional Arel features. Other features of this gem do not require these to be available or configured in any way. They are indeed used internally, but without the external exposure. Feel free to change, configure, and use them as desired.

## Arel Function Node builder

The `Arel::Nodes::NamedFunction.new` is not very developer-friendly, and there are a few things that are sometimes harder to do with it. Because of that, the gem has the [`Torque::PostgreSQL::Function`](https://github.com/crashtech/torque-postgresql/blob/master/lib/torque/postgresql/function.rb) helper to shortcut and facilitate such node building.

You can make this helper available anywhere by just setting the [`arel.expose_function_helper_on`](/postgresql/getting-started/configuring/#arel.expose_function_helper_on) config. For example, setting it to `'PG::Fn'` makes the following features available through it:

### Bind value

When building Arel nodes that include raw values, it is more accurate to provide such values via binds. They work better with prepared statements and queries can have improved caching. However, it's not really easy to build them, so these methods facilitate that:

```ruby
PG::Fn.bind(:title, 'Example', ActiveRecord::Type::String.new)    # It returns a bind param for your query
PG::Fn.bind_for(Video, :title, 'Example')                         # It pulls the type from the active model
PG::Fn.bind_with(Video.arel_table['title'], 'Example')            # It pulls the type from the type caster of the arel attribute
```

#### Bind type

The `bind_type` helper is mostly used for binding values that are not directly associated with columns. Most commonly used when given arguments to functions. It will use the `type` given as the second argument (Symbols will be translated into a proper `ActiveModel::Type`) or translate the Ruby class into the proper `ActiveModel` type.

```ruby
PG::Fn.bind_type(123)                    # Creates a ActiveModel::Type::Integer bind param
PG::Fn.bind_type(123, :string)           # Creates a ActiveModel::Type::String bind param
PG::Fn.bind_type(123, cast: :numeric)    # Writes the query casting the bind param, as in `$1::numeric`
```

### Infix operation

This is a shortcut for the `Arel::Nodes::InfixOperation`, which is widely used in the gem, so it needed to be easily accessible.

```ruby
                                                                                  # The operator is not checked!
PG::Fn.infix('@!', Video.arel_table['title'], Video.arel_table['description'])    # Produces "videos"."title" @! "videos"."description"
```

### Concat

A shortcut to build a proper chain of concatenation (` || `) nodes.

```ruby
PG::Fn.concat(Video.arel_table['title'])                                                                   # Produces "videos"."title"
PG::Fn.concat(Video.arel_table['title'], Video.arel_table['subtitle'])                                     # Produces "videos"."title" || "videos"."subtitle"
PG::Fn.concat(Video.arel_table['title'], Video.arel_table['subtitle'], Video.arel_table['description'])    # Produces "videos"."title" || "videos"."subtitle" || "videos"."description"
```

### Group By

A helper that allows calling `.group` on a query, giving an `Arel` node, which will cause calculation queries (like `.count`) to be performed correctly.

```ruby
# SELECT COUNT(*) AS "count_all", "users"."deleted_at" IS NULL AS "deleted" FROM "users" GROUP BY "deleted"
User.group(PG::Fn.group_by(User.arel_table['deleted_at'].eq(nil), 'deleted')).count
```

### Method missing

You can call any function on this helper and it will turn it into an `Arel::Nodes::NamedFunction` with the given arguments.

```ruby
                                                                            # The existence of the function is not checked!
PG::Fn.lower(Video.arel_table['title'])                                     # Produces LOWER("videos"."title")
PG::Fn.coalesce(Video.arel_table['title'], Video.arel_table['subtitle'])    # Produces COALESCE("videos"."title", "videos"."subtitle")
PG::Fn.something_else(Video.arel_table['title'])                            # Produces SOMETHING_ELSE("videos"."title")
```

## Document properties

`arel_property_of` builds the node for a path into a `json` or `jsonb` column, cast to what a [struct](/postgresql/data-types/struct/#the-arel-node) class declares for it when the column is backed by one.

```ruby
# ("videos"."metadata" #>> ARRAY['file', 'duration'])
Video.arel_property_of(:metadata, :file, :duration)

Video.order(Video.arel_property_of(:metadata, :file, :duration).desc)
```

## Infix operators

PostgreSQL allows a bunch of custom operators while working with [Arrays](https://www.postgresql.org/docs/9.6/functions-array.html), [Ranges](https://www.postgresql.org/docs/9.6/functions-range.html), and [Hashes](https://www.postgresql.org/docs/9.6/hstore.html).

Now with the [`arel.infix_operators`](/postgresql/getting-started/configuring/#arel.infix_operators) config, you can set up all the ones that are used and take advantage of the method being available on any `Arel::Nodes::Node` and `Arel::Attributes::Attribute`. These are the ones configured by default (method => operator):

```
.contained_by        => <@
.has_key             => ?
.has_all_keys        => ?&
.has_any_keys        => ?|
.strictly_left       => <<
.strictly_right      => >>
.doesnt_right_extend => &<
.doesnt_left_extend  => &>
.adjacent_to         => -|-
.matches_lquery      => ~
.matches_any_lquery  => ?
```

## Cast values

One of the things that enabled array associations and period operations is the ability to cast things from one type to another directly on Arel. This means that time columns can be cast into dates and have all the capabilities of a normal Arel node. Rails `8.0.2` introduces the same method with a small difference, so now there are two methods available: `.cast` and `.pg_cast`.

If you are used to Arel, to cast something, it's pretty simple:
```ruby
Event.arel_table[:created_at].cast(:date)
```
which will produce
```sql
CAST("events"."created_at" AS date)   -- Rails >= 8.0.2
"events"."created_at"::date           -- Rails < 8.0.2 or using .pg_cast
```
