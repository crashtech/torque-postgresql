---
title: Predicate Builder
section: querying
description: This is just somewhat specific to PostgreSQL, but mostly an enhancement
  to Rails ActiveRecord::PredicateBuilder, whose primary purpose is to make .where
  an
---

This is just somewhat specific to PostgreSQL, but mostly an enhancement to Rails `ActiveRecord::PredicateBuilder`, whose primary purpose is to make `.where` and `.where.not` calls in the format for `(attribute: value)` correctly translate into several distinct Arel and SQL operations. Its sole purpose is to ease the process of writing queries, without the need to use Arel directly for everything.

The inspiration for these features, and some notable examples, is the handling of `Array`, `Range`, and `ActiveRecord::Base` (A model). Each one of them gives the developer exactly what they would expect from their respective operation. That said, here are a few more options that are now made available.

You can pick and choose the ones you want enabled/disabled using [`predicate_builder.enabled`]({{ site.baseurl }}/getting-started/configuring/#predicate_builder.enabled) config.

## `Regexp`

Translate the given Regexp into a bind param while identifying the proper infix operator to use based on the case-insensitive indicator.

```ruby
Video.where(title: /(one|two)/)     # WHERE "videos"."title" ~ '(one|two)'
Video.where(title: /(one|two)/i)    # WHERE "videos"."title" ~* '(one|two)'
```

## `Enumerator::Lazy`

The rare use of `[].lazy`, where we would usually have to call `.force`, but there are cases where we would like to support both lazy and non-lazy operations simultaneously. This also makes it safe to use due to [`predicate_builder.lazy_timeout`]({{ site.baseurl }}/getting-started/configuring/#predicate_builder.lazy_timeout) and [`predicate_builder.lazy_limit`]({{ site.baseurl }}/getting-started/configuring/#predicate_builder.lazy_limit), which limit the resources used.

```ruby
Video.where(user_id: [1,2].lazy)    # WHERE "videos"."user_id" IN (1,2)
```

## `Arel::Attributes::Attribute`

At first, this may seem unnecessary. However, when working with joins, this can be particularly helpful.

```ruby
Video.joins(:tags).where(language: Tag.arel_table['language'])    # WHERE "videos"."language" = "tags"."language"
```

Another great advantage of this is the proper handling of array columns, which completely facilitated the operations of [Belongs to Many]({{ site.baseurl }}/models/belongs-to-many/) features.

```ruby
Video.where(tag_ids: Tag.arel_table['id'])          # WHERE "tags"."id" = ANY("videos"."tag_ids")
Tag.where(id: Video.arel_table['tag_ids'])          # WHERE "tags"."id" = ANY("videos"."tag_ids")
Video.where(tag_ids: User.arel_table['tag_ids'])    # WHERE "videos"."tag_ids" && "users"."tag_ids"
```

## `Array`

> This feature needs to be enabled via [`predicate_builder.handle_array_attributes`]({{ site.baseurl }}/getting-started/configuring/#predicate_builder.handle_array_attributes) because it may break the current state of your application if you have been using `.where` with array columns and any type of value (eg, `.where(tag_ids: [1,2,3])`).

The primary purpose of this feature is to more accurately convey the meaning of array and non-array values in these operations. It only takes place when `.where` is used against an array column.

```ruby
Video.where(tag_ids: [1,2,3])    # WHERE "videos"."tag_ids" && '{1,2,3}'
Video.where(tag_ids: 1)          # WHERE 1 = ANY("videos"."tag_ids")
Video.where(tag_ids: [])         # WHERE CARDINALITY("videos"."tag_ids") = 0
```

## `Hash` on a composite column

A `Hash` given to a [composite]({{ site.baseurl }}/data-types/composite/) column is broken down
into one condition per column of the type, and every pair is sent back through the predicate
builder. That means the whole `where` vocabulary above is available inside a composite, including
ranges and arrays, and it nests as deep as the type does.

```ruby
Place.where(home: { street: 'Main' })
# WHERE ("places"."home")."street" = 'Main'

Place.where(home: { number: 1..5 })
# WHERE ("places"."home")."number" BETWEEN 1 AND 5

Place.where(home: { street: %w[A B] })
# WHERE ("places"."home")."street" IN ('A', 'B')

Place.where(location: { base: { street: 'X' } })
# WHERE (("places"."location")."base")."street" = 'X'
```

An instance is compared as a whole record instead, which keeps the condition able to use an index.
On an array column, a whole value asks whether any entry matches it, while a `Hash` asks whether
any entry matches the columns it describes.

```ruby
Place.where(home: address)
# WHERE "places"."home" = '("Main",,"9",)'::address

Place.where(offices: address)
# WHERE '("Main",,"9",)'::address = ANY("places"."offices")

Place.where(offices: { street: 'Main' })
# WHERE EXISTS (
#   SELECT 1 FROM UNNEST("places"."offices") "address"
#   WHERE ("address")."street" = 'Main'
# )
```

> **Note** A key that is not a column of the type raises an `ArgumentError`, instead of being
> silently ignored. See [composite]({{ site.baseurl }}/data-types/composite/#querying) for the
> full behavior.

## `Hash` on a struct column

A [struct]({{ site.baseurl }}/data-types/struct/) column works the same way, over the properties
of the document rather than the columns of a type. Each value is cast to the type its class
declares before the comparison, so the condition is typed rather than a plain string match.

```ruby
Profile.where(settings: { theme: 'dark' })
# WHERE ("profiles"."settings" #>> ARRAY['theme']) = 'dark'

Profile.where(settings: { notifications: true })
# WHERE ("profiles"."settings" #>> ARRAY['notifications'])::boolean = TRUE

Profile.where(settings: { theme: %w[light dark] })
# WHERE ("profiles"."settings" #>> ARRAY['theme']) IN ('light', 'dark')

Profile.where(settings: { address: { city: 'SP' } })
# WHERE ("profiles"."settings" #>> ARRAY['address', 'city']) = 'SP'
```

> **Note** Only `jsonb` columns can be queried by their properties, because `json` has no
> operators for it, and a `json` column raises an `ArgumentError`. See
> [struct]({{ site.baseurl }}/data-types/struct/#querying) for the full behavior.
