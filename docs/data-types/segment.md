---
title: Segment
section: data-types
description: Segment original implementation.
---

Segment original implementation. Provides an easy interface to manipulate, save and restore, segment-like values from the database. Works very similarly to `ActiveRecord::Point`, but for a list of 2 values of them (stored as `x1`, `y1`, `x2`, `y2`). [PostgreSQL Docs](https://www.postgresql.org/docs/9.6/datatype-geometric.html#DATATYPE-LSEG)

The biggest difference between this and a [`line`](/postgresql/data-types/line/) is that its composition is based on two points.

## Migration

Just set the type of the column as `segment` when creating a table.
```ruby
create_table "hits" do |t|
  t.string  "source", null: false
  t.segment "trajectory"
end
```

## Using it

The column is automatically identified and its value turned into what is defined in [`geometry.segment_class`](/postgresql/getting-started/configuring/#geometry.segment_class) or into a `Torque::PostgreSQL::Segment`. 

This original implementation provides a couple of methods:
```ruby
hit = Hit.new
hit.trajectory.x1
hit.trajectory.y1
hit.trajectory.x2
hit.trajectory.y2
```

The value can be set in a few different ways:

```ruby
hit.trajectory = '3,2,15,10'
hit.trajectory = '[3,2],[15,10]'
hit.trajectory = '((3,2),(15,10))'
hit.trajectory = [3,2,15,10]
hit.trajectory = [[3,2],[15,10]]
hit.trajectory = { x1: 3, y1: 2, x2: 15, y2: 10 }
```
