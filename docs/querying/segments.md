---
title: Segments
section: querying
description: This feature uses the FILTER clause of aggregate functions to run several
  named calculations over the same query, each one restricted to its own condition.
---

> Several counters, one query! Menus and scopes counters have never been easier to implement.

This feature uses the `FILTER` clause of aggregate functions to run several named calculations over the same query, each one restricted to its own condition. [PostgreSQL Docs](https://www.postgresql.org/docs/current/sql-expressions.html#SYNTAX-AGGREGATES)

You can disable this feature using [config.segments](/postgresql/getting-started/configuring/#segments).

## How to

The `.segments` method maps names to conditions. It does not change how records are loaded; it changes what calculations return. Instead of a single value, `.count`, `.sum`, `.average`, `.minimum`, and `.maximum` return a `Hash` with one value per segment, and the aggregate is the same one you asked for.

```ruby
User.segments(adults: { age: 18.. }, minors: { age: ...18 }).count
# Expect { adults: 12, minors: 3 }

User.segments(adults: { age: 18.. }, minors: { age: ...18 }).sum(:age)
# Expect { adults: 480, minors: 21 }
```

```sql
SELECT COUNT(*) FILTER (WHERE "users"."age" >= 18) AS "adults",
       COUNT(*) FILTER (WHERE "users"."age" < 18) AS "minors"
FROM "users";
```

A segment can be anything that produces a relation. Its `WHERE` clause becomes the `FILTER`:

```ruby
Post.segments(
  all:       nil,                                          # No filter, the plain aggregate
  drafts:    { status: :draft },                           # A hash or string accepted by .where
  tested:    :test_scope,                                  # A scope name
  authored:  Post.where.not(author_id: nil),               # A relation
  published: -> { where(status: :published) },             # A proc evaluated on the model
  titled:    Post.arel_table[:title].not_eq(nil),          # An Arel predicate
  featured:  [:published, :test_scope, { pinned: true }],  # An array applies each item in order
  recent:    [['created_at > ?', 1.week.ago]],             # Where arguments go inside the array
).count
```

An array is a list of conditions applied one after the other, so several scopes can be combined into one segment. Because of that, the `where` argument style with placeholders has to be wrapped in the array as a single item.

A `nil` (or blank) condition keeps the aggregate unfiltered, which is handy for a total next to the segments. Any other condition that ends up filtering nothing raises an `ArgumentError`, since it is most likely a mistake.

Segments merge across calls and across relations, and can be removed with `.unscope(:segments)`:

```ruby
User.segments(adults: { age: 18.. }).segments(minors: { age: ...18 })
User.where(role: :admin).merge(User.segments(adults: { age: 18.. }))
User.segments(adults: { age: 18.. }).unscope(:segments).count   # Expect N
```

## Grouping

When the query is grouped, the segments are nested under each group key, following the same rules of a regular grouped calculation. It also composes with [buckets](/postgresql/querying/buckets/).

```ruby
User.group(:role).segments(adults: { age: 18.. }, minors: { age: ...18 }).count
# Expect { 'visitor' => { adults: 4, minors: 1 }, 'admin' => { adults: 8, minors: 2 } }

User.group(:role, :name).segments(adults: { age: 18.. }).count
# Expect { ['visitor', 'Rick'] => { adults: 1 }, ... }

User.buckets(:age, 0..100, count: 5).segments(admins: { role: :admin }).count
# Expect { (0...20) => { admins: 1 }, (20...40) => { admins: 3 }, ... }
```

```sql
SELECT "users"."role" AS "users_role",
       COUNT(*) FILTER (WHERE "users"."age" >= 18) AS "adults",
       COUNT(*) FILTER (WHERE "users"."age" < 18) AS "minors"
FROM "users"
GROUP BY "users"."role";
```

Grouping by a `belongs_to` association name, `limit`/`offset` on the calculation, and `having` are not supported when segments are present.
