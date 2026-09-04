---
title: Enum
section: data-types
description: Enum type manager.
---

Enum type manager. For each enum-type created on the database, it allows 2 behaviors: Single enum attribution, Array (Set-like) attribution. For [Array attribution](/postgresql/data-types/enum-set/) check the link. It creates a separated class to hold each enum set that can be used by multiple models, it also keeps the database consistent. The enum type is known to have a better performance against string- and integer-like enums. [PostgreSQL Docs](https://www.postgresql.org/docs/9.6/static/datatype-enum.html)

## Migration

First, you have to create the enum during your migration, since it's the database that holds the list of possible values.
```ruby
create_enum :roles, %i(visitor manager admin)
```

On Rails older than 7.0, where the gem still provided `create_enum`, the values could also be prefixed or suffixed:
```ruby
# ['status_foo', 'status_bar']
create_enum :status, %i(foo bar), prefix: true
# ['foo_tst', 'bar_tst']
create_enum :status, %i(foo bar), suffix: 'tst'
```

> **Note** Rails now ships its own `create_enum`, so the gem removed its version — and with it the `prefix` and `suffix` options above. `add_enum_values` still exists only in this gem.

You can also manage this type alongside other migrations, renaming, adding values, or deleting it.
```ruby
# Rename enum by renaming the type it represents
rename_type :status, :content_status

# Adding values
add_enum_values :status, %i(baz qux)                      # To the end of the list
add_enum_values :status, %i(baz qux), prepend: true       # At the beginning of the list
add_enum_values :status, %i(baz qux), after: 'foo'        # After a certain value
add_enum_values :status, %i(baz qux), before: 'foo'       # Before a certain value
add_enum_values :status, %i(baz qux), prefix: true        # With type name as prefix
add_enum_values :status, %i(baz qux), suffix: 'tst'       # With a specific suffix

# Deleting an enum by dropping the type it represents
drop_type :status
```

Once you've created the type, you can use it while creating your table in three ways.
```ruby
create_table :users do |t|
  t.string :name
  t.role :role                              # Uses the type of the column, since enum is a type
  t.enum :status                            # Figures the type name from the column name    !! ONLY RAILS <  7.0
  t.enum :last_status, subtype: :status     # Explicit tells the type to be used            !! ONLY RAILS <  7.0
  t.enum :last_status, enum_type: :status   # This is the official Rails 7.0 syntax         !! ONLY RAILS >= 7.0
end
```

### Adding value migration Exception

Sometimes, adding values is prevented because migrations run inside of transactions, but there are some occasions that PostgreSQL doesn't allow that, check [PostgreSQL Docs](https://www.postgresql.org/docs/9.1/sql-altertype.html#AEN63251). In those cases, just add `disable_ddl_transaction!` to the migration:

```ruby
class AddEnumValue < ActiveRecord::Migration[5.2]
  disable_ddl_transaction!

  def up
    add_enum_values :status, %i(baz qux), after: :foo
  end

  def down
    # this migration is irreversible
  end
end
```

## The type Class

Each enum type loaded from the database will have its own class type of value, created under the [`enum.namespace`](/postgresql/getting-started/configuring/#enum.namespace) namespace.
```ruby
Enum::Roles

# You can get a representative value from there
Enum::Roles.admin

# Or you can get the list of values
Enum::Roles.values

# You can also get all the values as symbols
Enum::Roles.keys

# Allows you to iterate over the values directly from the class
Enum::Roles.each do |role|
  puts role
end

# You can use index-based references of a value
Enum::Roles.new(0)       # :visitor
Enum::Roles.admin.to_i   # 2
```

## Models

You have to go to each of your models and enable the functionality for each enum-type field. You don't need to provide the values since they will be loaded from the database. The method name is defined on [`enum.base_method`](/postgresql/getting-started/configuring/#enum.base_method).
```ruby
# models/user.rb
class User < ActiveRecord::Base
  torque_enum :role, :status
end
```

You are able to access the list of values through the class that holds the enum:
```ruby
User.roles         # List of strings
User.roles_keys    # List of symbols
```

You can set the column value from `String`, `Symbol`, and `Integer`:
```ruby
user = User.new
user.role = 'admin'    # :admin
user.role = :manager   # :manager
user.role = 0          # :visitor
```

A value that is not one of the type's values is kept as it is, so the database rejects it when
the record is saved, exactly like any other invalid input.

This allows you to compare values, or ask questions about it:
```ruby
other_user = User.new(role: :manager)
user = User.new(role: :manager)
user.role > :admin               # false
user.role == 1                   # true
user.role >= other_user.role     # true
user.role.manager?               # true
user.visitor?                    # false
```

The `bang!` methods are controlled by the [`enum.save_on_bang`](/postgresql/getting-started/configuring/#enum.save_on_bang):
```ruby
# The following will only perform a save on the database if enum.save_on_bang is set to true
user = User.new(role: :manager)
user.admin!
```

You can reach the I18n translations in three different ways, and the scopes are configured on [`enum.i18n_scopes`](/postgresql/getting-started/configuring/#enum.i18n_scopes). On the third one, only the scopes on [`enum.i18n_type_scopes`](/postgresql/getting-started/configuring/#enum.i18n_type_scopes) are used, which allows per-model customization.
```ruby
user = User.new(role: :manager)
user.role.text                # User's manager
user.role_text                # User's manager
Enum::Roles.manager.text      # Manager
```

### Scopes

For each value, the model where the enum was defined receives additional scopes, making it easy to filter records.

```ruby
User.manager    # SELECT * FROM "users" WHERE "users"."role" = 'manager'
```

## Testing

When testing models or creating records using factories, `Enum` provides an easy way to get a random value from the list of any enum types. Besides the normal `User.roles.sample`, you can also use:

```ruby
Enum.sample(:roles)
```
