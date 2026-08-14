---
title: Belongs to Many
section: modeling
description: Belongs to an array of records, storing those locally.
---

> It's so nice to be able to say that my videos belong to many tags! So clear and simple! Love it!

Belongs to an array of records, storing those locally. The original `belongs_to` association defines a `SingularAssociation`, which means that it could be extended with `array: true`. In this case, I decided to create my own `CollectionAssociation` called `belongs_to_many`, which behaves similarly to the single one, but stores and returns a list of records. This was only possible due to PostgreSQL arrays and the new [Arel]({{ site.baseurl }}/querying/arel/) infix operators. [PostgreSQL Docs](https://www.postgresql.org/docs/9.6/arrays.html)

With this, now you can say things like `Project belongs to many employees`, which is more syntactically correct than `Project has many employees`.

## Migration

The only difference here, while creating the association, is that you just need to set the column as an array. The `references` or similar helpers are not yet available.

```ruby
create_table "employee" do |t|
  t.string "name"
end

create_table "project" do |t|
  t.bigint "employee_ids", array: true
  t.string "title"
end
```

## Model

Now go to the model and simply activate the feature using the `belongs_to_many` method, similar to how you would do with `belongs_to`.

```ruby
# models/project.rb
class Project < ApplicationRecord
  belongs_to_many :employees
end
```

That's it. The features provided with this are a middle point between `belongs_to` and `has_many`, which means that the records are returned as a list on `CollectionProxy`, but things like `touch` are also available.

**One important notice** is that polymorphism is not allowed for array-like associations, because the tuples can't be guaranteed every time.

Most of the options are just like the `has_many` association, but they also include:

- `touch`: If true, the associated objects will be touched (the updated_at/on attributes set to current time) when this record is either saved or destroyed. Default: `false`
- `optional`: When set to **true**, the association will not have its presence validated. Default: `true`
- `required`: When set to **true**, the association will also have its presence validated. Default: `false`
- `dependent`: Controls what happens to the associated objects when their owner is destroyed. Default: `:nullify`
- `primary_key`: The name of the column on the foreign table that connects to the array. Default: `:id`
- `foreign_key`: The name of the array column used to store the association IDs locally. Default: `:"#{name.singular}_ids"`

There are no additional or custom features on top of those provided by a normal `has_many` association.

## Combined with [Predicate Builder]({{ site.baseurl }}/querying/predicate-builder/#array)

You can enable enhancements to Rails' `PredicateBuilder` to simplify how you query the association column even further.

```ruby
# Without it
Project.where(Project.arel_table['employee_ids'].overlaps([1]))
# SELECT * FROM projects WHERE projects.employee_ids && '{1}';

# With it
Project.where(employee_ids: 1)
# SELECT * FROM projects WHERE 1 = ANY(projects.employee_ids);
```
