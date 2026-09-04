---
title: Date/Time Range
section: data-types
description: Date or time ranges features.
---

> I hope it's not only me that can't take `start_time` and `finish_time` **ANYMORE!!!**

Date or time ranges features. This provides extended and complex calculations over date and time ranges. In a few words, you can now store `start_time` and `finish_time` in the same column and rely on the methods provided here to do your magic. [PostgreSQL Docs](https://www.postgresql.org/docs/9.6/functions-range.html)

## Migration

Create a table with the single column set as any type of time/date range (`daterange`, `tsrange`, or `tstzrange`), like:
```ruby
create_table :events do |t|
  t.string   :name
  t.tsrange  :period
  t.interval :interval
end
```

## Models

You have to go to each of your models and enable the functionality for each range-type field. The method name is defined on [`period.base_method`](/postgresql/getting-started/configuring/#period.base_method).
```ruby
# models/event.rb
class Event < ActiveRecord::Base
  period_for :period
end
```

There are a couple of important settings that can be provided to this:
```ruby
# Pessimistic mode: an unset (nil) value is treated as false; by default the
# check is optimistic and a nil value is treated as true
period_for :period, pessimistic: true

# You can define a column or a value to be used as a threshold
period_for :period, threshold: :interval
period_for :period, threshold: 15.minutes

# This will force the creation of all the methods, which would raise an exception on conflicting. The default is false
period_for :period, force: true

# If you don't want the methods to have the field name, then you can use this option
period_for :period, prefixed: false

# You can also rename any method that will be created
period_for :period, methods: { current: :ongoing, current?: :ongoing? }
```

You can check the list of the methods that will be created on the configuration page for [`period.method_names`](/postgresql/getting-started/configuring/#period.method_names).

## Scopes

This is where the period has its best features. With now provided [Arel](/postgresql/querying/arel/) operators, a bunch of well-prepared statements can be used to query the records.

The `default` represents what was defined by the opposite of `pessimistic` option. If `pessimistic` is `TRUE`, then querying against `NULL` values will result in `FALSE`.

### `:current_on` as `.period_on(time)`
It basically checks if the range contains the given value or Arel attribute.  
```sql
COALESCE(NULLIF("events"."period", tsrange(NULL,NULL)) @> value, default)
-- With threshold
COALESCE(NULLIF(tsrange(LOWER("events"."period") - "events"."interval",UPPER("events"."period") + "events"."interval"), tsrange(NULL,NULL)) @> value, default)
```

### `:current` as `.current_period`
Checks if the period contains the current time/date.  
```sql
COALESCE(NULLIF("events"."period", tsrange(NULL,NULL)) @> Time.zone.now, default)
-- With threshold
COALESCE(NULLIF(tsrange(LOWER("events"."period") - "events"."interval",UPPER("events"."period") + "events"."interval"), tsrange(NULL,NULL)) @> Time.zone.now, default)
```

### `:not_current` as `.not_current_period`
The opposite version of the `:current` scope.  
```sql
NOT COALESCE(NULLIF("events"."period", tsrange(NULL,NULL)) @> Time.zone.now, default)
-- With threshold
NOT COALESCE(NULLIF(tsrange(LOWER("events"."period") - "events"."interval",UPPER("events"."period") + "events"."interval"), tsrange(NULL,NULL)) @> Time.zone.now, default)
```

### `:containing` as `.period_containing(value)`
Checks if the value is contained in the range. You can pass either an Arel attribute or a plain value.  
```sql
"events"."period" @> value
```

### `:not_containing` as `.period_not_containing(value)`
The opposite version of the `:containing` scope.  
```sql
NOT "events"."period" @> value
```

### `:overlapping` as `.period_overlapping(left, right = nil)`
Checks if two ranges overlap. You can pass either another range column as an Arel attribute, a plain range on the left, or the 2 parts of a range.  
```sql
"events"."period" && value
-- OR
"events"."period" && tsrange(left, right)
```

### `:not_overlapping` as `.period_not_overlapping(left, right = nil)`
The opposite version of the `:overlapping` scope.  
```sql
NOT "events"."period" && value
-- OR
NOT "events"."period" && tsrange(left, right)
```

### `:starting_after` as `.period_starting_after(value)`
Filter records whose left value is greater than the one provided, which can be either an Arel attribute or a plain value.  
```sql
LOWER("events"."period") > value
```

### `:starting_before` as `.period_starting_before(value)`
Filter records whose left value is less than the one provided, which can be either an Arel attribute or a plain value.  
```sql
LOWER("events"."period") < value
```

### `:finishing_after` as `.period_finishing_after(value)`
Filter records whose right value is greater than the one provided, which can be either an Arel attribute or a plain value.  
```sql
UPPER("events"."period") > value
```

### `:finishing_before` as `.period_finishing_before(value)`
Filter records whose right value is less than the one provided, which can be either an Arel attribute or a plain value.  
```sql
UPPER("events"."period") < value
```

### `:real_containing` as `.period_real_containing(value)` **(ONLY WITH THRESHOLD)**
Checks if the value is contained in the range while considering the threshold. You can pass either an Arel attribute or a plain value.  
```sql
tsrange(LOWER("events"."period") - "events"."interval",UPPER("events"."period") + "events"."interval") @> value
```

### `:real_overlapping` as `.period_real_overlapping(left, right = nil)` **(ONLY WITH THRESHOLD)**
Checks if two ranges overlap while considering the threshold. You can pass either another range column as an Arel attribute, a plain range on the left, or the 2 parts of a range.  
```sql
tsrange(LOWER("events"."period") - "events"."interval",UPPER("events"."period") + "events"."interval") && value
-- OR
tsrange(LOWER("events"."period") - "events"."interval",UPPER("events"."period") + "events"."interval") && tsrange(left, right)
```

### `:real_starting_after` as `.period_real_starting_after(value)` **(ONLY WITH THRESHOLD)**
Filter records whose left value with the threshold is greater than the one provided, which can be either an Arel attribute or a plain value.  
```sql
(LOWER("events"."period") - "events"."interval") > value
```

### `:real_starting_before` as `.period_real_starting_before(value)` **(ONLY WITH THRESHOLD)**
Filter records whose left value with the threshold is less than the one provided, which can be either an Arel attribute or a plain value.  
```sql
(LOWER("events"."period") - "events"."interval") < value
```

### `:real_finishing_after` as `.period_real_finishing_after(value)` **(ONLY WITH THRESHOLD)**
Filter records whose right value with the threshold is greater than the one provided, which can be either an Arel attribute or a plain value.  
```sql
(UPPER("events"."period") + "events"."interval") > value
```

### `:real_finishing_before` as `.period_real_finishing_before(value)` **(ONLY WITH THRESHOLD)**
Filter records whose right value with the threshold is less than the one provided, which can be either an Arel attribute or a plain value.  
```sql
(UPPER("events"."period") + "events"."interval") < value
```

### `:containing_date` as `.period_containing_date(value)` **(NON DATERANGE ONLY)**
Checks if the value is contained in the range as date. You can pass either an Arel attribute or a plain value.  
```sql
daterange(LOWER("events"."period")::date,UPPER("events"."period")::date) @> value
```

### `:not_containing_date` as `.period_not_containing_date(value)` **(NON DATERANGE ONLY)**
The opposite version of the `:containing_date` scope.  
```sql
NOT daterange(LOWER("events"."period")::date,UPPER("events"."period")::date) @> value
```

### `:overlapping_date` as `.period_overlapping_date(left, right = nil)` **(NON DATERANGE ONLY)**
Checks if two ranges overlap but comparing only dates. You can pass either another range column as an Arel attribute, a plain range on the left, or the 2 parts of a range.  
```sql
daterange(LOWER("events"."period")::date,UPPER("events"."period")::date) && value
-- OR
daterange(LOWER("events"."period")::date,UPPER("events"."period")::date) && daterange(left, right)
```

### `:not_overlapping_date` as `.period_not_overlapping_date(left, right = nil)` **(NON DATERANGE ONLY)**
The opposite version of the `:overlapping_date` scope.  
```sql
NOT daterange(LOWER("events"."period")::date,UPPER("events"."period")::date) && value
-- OR
NOT daterange(LOWER("events"."period")::date,UPPER("events"."period")::date) && daterange(left, right)
```

### `:real_containing_date` as `.period_real_containing_date(value)` **(NON DATERANGE ONLY)**
Checks if the value is contained in the range as date and considering the threshold. You can pass either an Arel attribute or a plain value.  
```sql
daterange((LOWER("events"."period") - "events"."interval")::date,(UPPER("events"."period") + "events"."interval")::date) @> value
```

### `:real_overlapping_date` as `.period_real_overlapping_date(left, right = nil)` **(NON DATERANGE ONLY)**
Checks if two ranges overlap but comparing only dates and considering the threshold. You can pass either another range column as an Arel attribute, a plain range on the left, or the 2 parts of a range.  
```sql
daterange((LOWER("events"."period") - "events"."interval")::date,(UPPER("events"."period") + "events"."interval")::date) && value
-- OR
daterange((LOWER("events"."period") - "events"."interval")::date,(UPPER("events"."period") + "events"."interval")::date) && daterange(left, right)
```

## Instance methods

A couple of instance methods are provided as well.

### `:current?` as `.current_period?`
Check if the value on the column represents a current period.  
```ruby
(period.min < Time.zone.now && period.max > Time.zone.now) || default
```

### `:current_on?` as `.current_period_on?(value)`
Similar to the above one, but allowing a value to be passed.  
```ruby
(period.min < value && period.max > value) || default
```

### `:start` as `.period_start`
Get the beginning of the period.  
```ruby
period.min
```

### `:finish` as `.period_finish`
Get the ending of the period.  
```ruby
period.max
```

### `:real` as `.real_period` **(ONLY WITH THRESHOLD)**
Get the real range period while considering the threshold.  
```ruby
((period.min - threshold)..(period.max + threshold))
```

### `:real_start` as `.period_real_start` **(ONLY WITH THRESHOLD)**
Get the beginning of the period while considering the threshold.  
```ruby
period.min - threshold
```

### `:real_finish` as `.period_real_finish` **(ONLY WITH THRESHOLD)**
Get the ending of the period while considering the threshold.  
```ruby
period.max + threshold
```
