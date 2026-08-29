---
title: Distinct On
section: querying
description: MySQL-like group by statements on queries.
---

MySQL-like group by statements on queries. It keeps only the first row of each set of rows where the given expressions evaluate to equal. [PostgreSQL Docs](https://www.postgresql.org/docs/9.6/static/sql-select.html#SQL-DISTINCT)

## How it works
```ruby
distinct_on(*columns)
```

Just send the list of fields to be included on the `DISTINCT ON` statement:
```ruby
# SELECT DISTINCT ON ( "users"."name" ) "users".* FROM "users"
User.distinct_on(:name).all
```

You can use where-like syntax to find more complex columns:
```ruby
# SELECT DISTINCT ON ( "photos"."type" ) "users".* FROM "users" INNER JOIN "photos" ON "users"."id" = "photos"."user_id"
User.joins(:photos).distinct_on(photos: :type).all

# SELECT DISTINCT ON ( "photos"."type", "photos"."size" ) "users".* FROM "users" INNER JOIN "photos" ON "users"."id" = "photos"."user_id"
User.joins(:photos).distinct_on(photos: [:type, :size]).all
```

The same syntax reaches a property of a [struct]({{ site.baseurl }}/data-types/struct/) column or a column of a [composite]({{ site.baseurl }}/data-types/composite/) one:
```ruby
# SELECT DISTINCT ON ( ("profiles"."settings" #>> ARRAY['theme']) ) "profiles".* FROM "profiles"
Profile.distinct_on(settings: :theme).all
```
