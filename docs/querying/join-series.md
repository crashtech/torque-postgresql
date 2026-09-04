---
title: Join Series
section: querying
description: This feature produces a join of your main query against a generate_series()
  function result.
---

> Part 1 of the report `series`

This feature produces a join of your main query against a `generate_series()` function result. The main motivation behind this feature was the generation of reports. More specifically, reports using `created_at` that would originally cause undesired rows in the output. [PostgreSQL Docs](https://www.postgresql.org/docs/current/functions-srf.html)

You can disable this feature using [`config.join_series`](/postgresql/getting-started/configuring/#join_series).

## How to

The `join_series` will basically generate a proper join between the `generate_series()` PG function, using a `Range` as base, and the column provided on the `with:` argument.

```ruby
# SELECT "users".* FROM "users" INNER JOIN GENERATE_SERIES(0::integer, 100::integer) AS series ON "series" = "users"."age"
User.join_series(0..100, with: :age)
```

The range can be of any type, including dates and times. Here is a list of all options that can be used to configure this operation:

- `with:` The column on the `ON` clause of the join. A `Hash` reaches a property of a [struct](/postgresql/data-types/struct/) column or a column of a [composite](/postgresql/data-types/composite/) one, as in `with: { home: :number }`;
- `as:` The name of the generated values;
- `step:` The step of the series generation. When using with dates and times, a duration (like `1.day`) must be provided;
- `mode:` The type of the join to use. Valid values are: `:inner` for `INNER JOIN`, `:left` for `LEFT OUTER JOIN`, `:right` for `RIGHT OUTER JOIN`, and `:full` for `FULL OUTER JOIN`;
- `cast:` A conditional casting for both sides (helpful when using against `created_at` columns matching against dates).
- `time_zone:` A time zone value or attribute. This extra parameter only works with [PostgreSQL >= 16.0](https://www.postgresql.org/docs/16/functions-srf.html).
- `{ |series, table| }` When provided with a block, you can customize exactly how the `ON` clause will be handled.

Here is a full example that will count the number of users created each day for January 2025.

```ruby
range = Date.new(2025, 1, 1)..Date.new(2025, 1, 31)
User.join_series(range, step: 1.day) do |series, table|
  series.pg_cast(:date).eq(table['created_at'].pg_cast(:date))
end.group('series').count
```

```sql
SELECT COUNT(*) AS "count_all", series AS "series"
FROM "users"
         INNER JOIN GENERATE_SERIES('2025-01-01 00:00:00'::timestamp, '2025-01-31 00:00:00'::timestamp, 'P1D'::interval) AS series
                    ON "series"::date = "users"."created_at"::date
GROUP BY series;
```

> Simplified example from `v4.0.1`, which will produce a more expected result/report

```ruby
range = Date.new(2025, 1, 1)..Date.new(2025, 1, 31)
result = User.join_series(range, with: :created_at, step: 1.day, cast: :date, mode: :right).group('series').count(:id)
# result => { 2025-01-01 00:00:00 UTC => 0, ... }
```

```sql
SELECT COUNT("users"."id") AS "count_id", series AS "series"
FROM "users"
         RIGHT OUTER JOIN GENERATE_SERIES('2025-01-01 00:00:00'::timestamp, '2025-01-31 00:00:00'::timestamp,
                                          'P1D'::interval) AS series
                          ON "series"::date = "users"."created_at"::date
GROUP BY series;
```
