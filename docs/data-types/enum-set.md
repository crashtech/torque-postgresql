---
title: EnumSet
section: data-types
description: Enum set type manager.
---

Enum set type manager. For each enum-type created on the database, it allows 2 behaviors: Single enum attribution, Array (Set-like) attribution. For [Single enum attribution]({{ site.baseurl }}/data-types/enum/) check the link. The enum type is known to have a better performance against string- and integer-like enums. Now with the array option, which behaves like binary assignment, each record can have multiple enum values. [PostgreSQL Docs](https://www.postgresql.org/docs/9.6/static/datatype-enum.html)

## Migration

First, you have to create the enum during your migration, since it's the database that holds the list of possible values.
```ruby
create_enum :permissions, %i(read write exec)
```

You can check more about the type creation on the [Enum docs]({{ site.baseurl }}/data-types/enum/).

Just as a reference, we will be using this table for the examples:
```ruby
create_table :posts do |t|
  t.string :title
  t.permissions :creator_permissions, array: true                            # ONLY RAILS <  7.0
  t.enum :creator_permissions, enum_type: :creator_permissions, array: true  # ONLY RAILS >= 7.0
end
```

If you want to add a default value that is an array containing elements, you will need to enable the `use_extended_defaults` setting. This is still experimental, so use it with caution.
```ruby
create_table :posts do |t|
  t.string :title
  t.permissions :creator_permissions, array: true, default: %w(read write exec)
end
```

## The type Class

Each enum type loaded from the database will have its own class type of value for sets, created under the [`enum.namespace`]({{ site.baseurl }}/getting-started/configuring/#enum.namespace) namespace.
```ruby
Enum::PermissionsSet

# You can get a representative value from there
Enum::PermissionsSet.read

# Or you can get the list of values
Enum::PermissionsSet.values

# You can also get all the values as symbols
Enum::PermissionsSet.keys

# Allows you to iterate over the values directly from the class
Enum::PermissionsSet.each do |permission|
  puts permission
end

# You can use index-based for power-based reference
Enum::PermissionsSet.new(0)       # []
Enum::PermissionsSet.new(3)       # [:read, :write]
Enum::PermissionsSet.exec.to_i    # 4
```

## Models

You have to go to each of your models and enable the functionality for each enum-set-type field. You don't need to provide the values since they will be loaded from the database. The method name is defined on [`enum.set_method`]({{ site.baseurl }}/getting-started/configuring/#enum.set_method).
```ruby
# models/user.rb
class Post < ActiveRecord::Base
  torque_enum_set :creator_permissions
end
```

You are able to access the list of values through the class that holds the enum set:
```ruby
Post.creator_permissions         # List of strings
Post.creator_permissions_keys    # List of symbols
```

You can set the column value from `String`, `Array`, `Symbol`, and `Integer`:
```ruby
post = Post.new
post.creator_permissions = 'read'           # [:read]
post.creator_permissions = :write           # [:write]
post.creator_permissions = [:read, :write]  # [:read, :write]
post.creator_permissions = 7                # [:read, :write, :exec]
```

A value that is not one of the type's values is kept as it is, so the database rejects it when
the record is saved, exactly like any other invalid input.

Given the power from the `to_i` operation, you can compare values, or ask questions about it:
```ruby
other_post = Post.new(creator_permissions: [:read])
post = Post.new(creator_permissions: [:write])
post.creator_permissions > :exec                            # false
post.creator_permissions == 2                               # true
post.creator_permissions >= other_post.creator_permissions  # true
post.creator_permissions.write?                             # true
post.read?                                                  # false
```

The `bang!` methods are controlled by the [`enum.save_on_bang`]({{ site.baseurl }}/getting-started/configuring/#enum.save_on_bang):
```ruby
# The following will only perform a save on the database if enum.save_on_bang is set to true
post = Post.new(creator_permissions: [:write])
post.read!
post.creator_permissions === [:read, :write]
```

You can reach the I18n translations in three different ways, and the scopes are configured on [`enum.i18n_scopes`]({{ site.baseurl }}/getting-started/configuring/#enum.i18n_scopes). On the third one, only the scopes on [`enum.i18n_type_scopes`]({{ site.baseurl }}/getting-started/configuring/#enum.i18n_type_scopes) are used, which allows per-model customization.
```ruby
post = Post.new(creator_permissions: [:read, :write])
post.creator_permissions.text         # Read post and Write post
post.creator_permissions_text         # Read post and Write post
Enum::PermissionsSet.read.text        # Read
```

## Set features

The value by itself behaves just like a [Set](https://ruby-doc.org/stdlib-2.5.1/libdoc/set/rdoc/Set.html), which allows all sorts of bitwise operations.

```ruby
post = Post.new(creator_permissions: [:read, :write])
post.creator_permissions & [:write]    # [:write]
post.creator_permissions & [:exec]     # []
post.creator_permissions | [:exec]     # [:read, :write, :exec]
post.creator_permissions -= :write     # [:read]
```

### Scopes

For each value, the model where the enum was defined receives additional scopes, making it easy to filter records.
```ruby
Post.write    # SELECT * FROM "posts" WHERE "posts"."creator_permissions" @> ARRAY['write']::permissions[]
              # Where @> means 'contains', and ::permissions[] means 'as an array of values from permissions enum type'
```

There are also additional scopes exclusively for enum set, where you can filter by whether all of the values must be present, or any of them.
```ruby
Post.has_creator_permissions('read', 'write')        # Records that have both 'read' and 'write' values
Post.has_any_creator_permissions('write', 'exec')    # Records that have 'write', 'exec', or both values
```

## Testing

When testing models or creating records using factories, `EnumSet` provides an easy way to get a random number of values from the list of any enum types. Besides the normal `Post.creator_permissions.sample`, you can also use:

```ruby
Enum.sample(:permissions_set)
```
