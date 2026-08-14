---
title: Circle
section: data-types
description: Circle original implementation.
---

Circle original implementation. Provides an easy interface to manipulate, save and restore, circle-like values from the database. Works very similarly to `ActiveRecord::Point`, but for a list of 1 point and 1 radius data (`x`, `y`, and `r`). [PostgreSQL Docs](https://www.postgresql.org/docs/9.6/datatype-geometric.html#DATATYPE-CIRCLE)

## Migration

Just set the type of the column as `circle` when creating a table.
```ruby
create_table "region" do |t|
  t.string "title", null: false
  t.circle "area"
end
```

## Using it

The column is automatically identified and its value turned into what is defined in [`geometry.circle_class`]({{ site.baseurl }}/getting-started/configuring/#geometry.circle_class) or into a `Torque::PostgreSQL::Circle`. 

This original implementation provides a couple of methods:
```ruby
region = Region.new
region.area.x
region.area.y
region.area.r
region.area.radius   # Same as r
region.area.center   # Which will return a point for the center
```

The value can be set in a few different ways:

```ruby
region.area = '10,10,5'
region.area = '[10,10],5'
region.area = '<(10,10),5>'
region.area = [10,10,5]
region.area = [[10,10],5]
region.area = { x: 10, y: 10, r: 5 }
```
