---
title: Cross Join
section: experimental
description: This feature joins the query against a set produced by a function, a subquery,
  or a list of rows, which becomes reachable by the name you give it.
---

> Rows from anywhere, side by side with every record

This feature joins the query against a set produced by a function, a subquery, or a list of rows, which becomes reachable by the name you give it. It is how PostgreSQL combines a table with set-returning functions like `unnest()`, with `LATERAL` subqueries, and with values that only exist on the Ruby side. [PostgreSQL Docs](https://www.postgresql.org/docs/current/queries-table-expressions.html#QUERIES-LATERAL)

It is disabled by default, since it is experimental and its API may still move. You can enable it via [`cross_join.enabled`](/postgresql/getting-started/configuring/#cross_join.enabled).

## How to

The `.cross_join` method takes the source of the rows and the name the result will have in the query. For example, a set-returning function:

```ruby
snippets = FN.unnest(Profile.arel_table[:snippets])
Profile.cross_join(snippets, as: :doc, columns: %i[value])
```

```sql
SELECT "profiles".* FROM "profiles"
CROSS JOIN UNNEST("profiles"."snippets") "doc"("value");
```

Here is a list of all options that can be used to configure this operation:

- `as:` The name of the joined set, which is how its columns are referenced in the query. Required;
- `columns:` The names of the columns produced by the source. A list of `Hash` rows names its own columns, everything else has to be told;
- `mode:` The type of the join to use. Valid values are: `:cross` for `CROSS JOIN` (default), and `:left` for `LEFT OUTER JOIN ... ON TRUE`, which keeps the records even when the source produces no rows;
- `with_ordinality:` Adds a counter column to the set. `true` names it after [`cross_join.ordinality_column`](/postgresql/getting-started/configuring/#cross_join.ordinality_column), and a `Symbol` or `String` names it directly.

### A list of rows

An `Array` of rows is sent as one `ARRAY` per column, which costs a single bind for each column instead of one for every value. `Hash` rows name their own columns and can be given in any key order. `Array` rows need `columns:`.

```ruby
Profile.cross_join([{ id: 1, label: 'a' }, { id: 2, label: 'b' }], as: :v)
Profile.cross_join([[1, 'a'], [2, 'b']], as: :v, columns: %i[id label])
```

```sql
SELECT "profiles".* FROM "profiles"
CROSS JOIN UNNEST(ARRAY[1, 2], ARRAY['a', 'b']) "v"("id", "label");
```

### A subquery

A relation or an `Arel::SelectManager` is joined as a `LATERAL` subquery, so it can reference the columns of the main query. Its binds are kept apart from the ones of the main query.

```ruby
other = Profile.select(:name).limit(1)
Profile.cross_join(other, as: :other, columns: %i[name])
```

```sql
SELECT "profiles".* FROM "profiles"
CROSS JOIN LATERAL (SELECT "profiles"."name" FROM "profiles" LIMIT 1) "other"("name");
```

### Left join and ordinality

A `:left` mode keeps the records of the main query even when the source produces nothing for them:

```ruby
Profile.cross_join(snippets, as: :doc, mode: :left)
```

```sql
SELECT "profiles".* FROM "profiles"
LEFT OUTER JOIN UNNEST("profiles"."snippets") "doc" ON TRUE;
```

The counter column goes last in the alias list:

```ruby
Profile.cross_join(snippets, as: :doc, columns: %i[value], with_ordinality: true)
Profile.cross_join(snippets, as: :doc, columns: %i[value], with_ordinality: :idx)
```

```sql
SELECT "profiles".* FROM "profiles"
CROSS JOIN UNNEST("profiles"."snippets") WITH ORDINALITY "doc"("value", "ordinality");
```

PostgreSQL matches the alias list positionally, so naming the counter requires naming every other column as well. Without `columns:`, only the name `ordinality` can be promised, and any other name raises an `ArgumentError`.

## Reaching the joined columns

The joined set is reachable through SQL for now, so its columns go through `Arel.sql` on `select`, `pluck`, `where`, and `order`. Values keep their type.

```ruby
Profile.cross_join([{ n: 10 }, { n: 20 }], as: :v).pluck(Arel.sql('"v"."n"'))
# Expect [10, 20] for each profile

Profile.cross_join([{ n: 'a' }, { n: 'b' }], as: :v, with_ordinality: true)
  .pluck(Arel.sql('"v"."ordinality"'))
# Expect [1, 2] for each profile
```

> **Note** Resolving the alias by name on `where` and `select`, like a regular column, is the part of this feature still being designed, which is why it is experimental.

## Composition

A join is stored under its name, so a second `cross_join` with the same `as:` replaces the first. Joins merge across relations, and can be removed with `.unscope(:cross_joins)` or `.except(:cross_joins)`. They are not part of the regular joins, so `.except(:joins)` keeps them.

```ruby
Profile.all.merge(Profile.cross_join(snippets, as: :doc))    # Keeps the join
Profile.cross_join(snippets, as: :doc).unscope(:cross_joins)  # Drops it
Profile.cross_join(snippets, as: :doc).except(:joins)        # Keeps it
```

## Errors

An `ArgumentError` is raised when the source is not an Arel node, a relation, or an `Array`; when the list of rows is empty; when `Array` rows are given without `columns:`; when `mode:` is anything other than `:cross` or `:left`; or when `with_ordinality:` names the counter while the columns of the source are unknown.
