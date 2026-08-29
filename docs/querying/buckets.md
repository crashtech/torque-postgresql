---
title: Buckets
section: querying
description: This feature uses the width_bucket() function to return results or produce
  calculations in which the results fall into the configured buckets.
---

> One more feature for the reports `bucket`

This feature uses the `width_bucket()` function to return results or produce calculations in which the results fall into the configured buckets. [PostgreSQL Docs](https://www.postgresql.org/docs/current/functions-math.html#width_bucket)

You can disable this feature using [config.buckets]({{ site.baseurl }}/getting-started/configuring/#buckets).

## How to

There are two main ways of using the `.buckets` function. Providing a `Range` or an `Array`. Both work the same way: Simply querying the records and getting a map/`Hash` where the key is the proper bucket (not the bucket number), and the value is the array of records; or using calculations like `.count`.

```ruby
# Range
User.buckets(:age, 0..100, count: 5)             # Expect { (0...20) => [...], (20...40) => [...], ... }
User.buckets(:age, 0..100, count: 10).count      # Expect { (0...10) => N, (10...20) => N, ... }

# Array
User.buckets(:role, %w[visitor manager admin])   # Expect { nil => [...], 'visitor' => [...], ... }
                                                 # nil represents values that did not fall on any bucket

# A property of a struct column, or a column of a composite one
Profile.buckets({ settings: :theme }, %w[dark light]).count
```
Here is a list of all options that can be used to configure this operation:

- `count:` When using a numeric range, this represents the number of buckets to divide the results into (it **DOES NOT** work as `.step`);
- `cast:` A shorthand for casting the values of the given `Array`;
- `as:` The name of the attribute added to the query and subsequent operations. Default `bucket`.

Here is a full example that will count the number of users created each year from 2010 until 2025.

```ruby
keys = 16.times.map { |add| Date.new(2010 + add) }
User.buckets(:created_at, keys, cast: :date).count
# Expect { Date.new(2010) => N, Date.new(2011) => N, ... }
```

```sql
SELECT COUNT(*) AS "count_all", WIDTH_BUCKET("users"."created_at", ARRAY[...]::date[]) AS "bucket"
FROM "users"
GROUP BY "bucket";
```

Since the resulting bucket attribute is added to the resulting query, you can access the raw value from each record:
```ruby
keys = 16.times.map { |add| Date.new(2010 + add) }
records = User.buckets(:created_at, keys, cast: :date).load

records.values.first.bucket       # Will return the numeric value of the bucket
```
