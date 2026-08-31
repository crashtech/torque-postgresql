---
title: Box
section: data-types
description: Box original implementation.
---

Box original implementation. Provides an easy interface to manipulate, save and restore, box-like values from the database. Works very similarly to `ActiveRecord::Point`, but for a list of 2 points each one with an `x` and `y` value. [PostgreSQL Docs](https://www.postgresql.org/docs/9.6/datatype-geometric.html#AEN7119)

## Migration

Just set the type of the column as `box` when creating a table.
```ruby
create_table "region" do |t|
  t.string "title", null: false
  t.box    "area"
end
```

## Using it

The column is automatically identified and its value turned into what is defined in [`geometry.box_class`](/postgresql/getting-started/configuring/#geometry.box_class) or into a `Torque::PostgreSQL::Box`. 

This original implementation provides a couple of methods:
```ruby
region = Region.new
region.area.x1
region.area.y1
region.area.x2
region.area.y2
region.area.points   # Which will return the 4 points of the box
```

The value can be set in a few different ways:

```ruby
region.area = '1,1,10,10'
region.area = '[1,1],[10,10]'
region.area = '((1,1),(10,10))'
region.area = [1,1,10,10]
region.area = [[1,1],[10,10]]
region.area = { x1: 1, y1: 1, x2: 10, y2: 10 }
```
