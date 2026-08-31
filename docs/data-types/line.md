---
title: Line
section: data-types
description: Line original implementation.
---

Line original implementation. Provides an easy interface to manipulate, save and restore, line-like values from the database. Works very similarly to `ActiveRecord::Point`, but for the values that compose a line (`a`, `b`, and `c`). [PostgreSQL Docs](https://www.postgresql.org/docs/9.6/datatype-geometric.html#DATATYPE-LINE)

The biggest difference between this and a [`segment`](/postgresql/data-types/segment/) is that its composition is based on the [`A, B, C` form](https://en.wikipedia.org/wiki/Line_(geometry)#In_Euclidean_geometry) (`0 = Ax + By + C`).

## Migration

Just set the type of the column as `line` when creating a table.
```ruby
create_table "Hit" do |t|
  t.string "source", null: false
  t.line   "trajectory"
end
```

## Using it

The column is automatically identified and its value turned into what is defined in [`geometry.line_class`](/postgresql/getting-started/configuring/#geometry.line_class) or into a `Torque::PostgreSQL::Line`. 

This original implementation provides a couple of methods:
```ruby
hit = Hit.new
hit.trajectory.a
hit.trajectory.b
hit.trajectory.c
hit.trajectory.horizontal?
hit.trajectory.cvertical?
hit.trajectory.intercept      # Same as c
```

The value can be set in a few different ways:

```ruby
hit.trajectory = '2,-5,4'
hit.trajectory = '{2,-5,4}'
hit.trajectory = [2,-5,4]
hit.trajectory = { a: 2, b: -5, c: 4 }
```
