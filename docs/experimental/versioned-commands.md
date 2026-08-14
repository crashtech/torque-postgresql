---
title: Versioned Commands
section: experimental
description: The idea behind this feature is to allow versioned schema objects to
  be properly managed without having to dump them all on schema.rb and not having
  to man
---

> Migrations with some SQL steroids

The idea behind this feature is to allow versioned schema objects to be properly managed without having to dump them all on `schema.rb` and not having to manually write `down` statements or explicitly indicate which version to go to. It can look a bit off-Rails, and for that reason, it is disabled by default. You can enable it via [`versioned_commands.enabled`]({{ site.baseurl }}/getting-started/configuring/#versioned_commands.enabled).

Once enabled, you will be able to manage `views`, `functions`, and non-enum `types` from `.sql` versioned migrations. The migration files themselves are expected to be reversible, which means they are validated against that capability. Each file is also validated against a "single" object operation (multiple functions are okay as long as they all have the same name).

## How to

You can use the provided generators (via `rails g`) `torque:view`, `torque:function`, and `torque:type` to create the proper migration file. There is not much beyond that. However, here is how these are managed:

### 1. A new `schema_versioned_commands` table

This table will exist as long as you have `versioned_commands` in your DB. This is an inherited table from `schema_migrations` that stores the `type` and `object_name` alongside the underlying `version`.

The table can be renamed using the [`versioned_commands.table_name`]({{ site.baseurl }}/getting-started/configuring/#versioned_commands.table_name) config.

### 2. A clean version of `schema.rb`

The dump of the schema will contain the minimum information about the versioned command, as per the example:

```ruby
# db/schema.rb
ActiveRecord::Schema.define(version: NNNN) do
  # ... extensions and enums
  # These are types managed by versioned commands
  create_type "type_example", version: 1

  # These are functions managed by versioned commands
  create_function "function_example", version: 2

  # ... tables and foreign keys
  # These are views managed by versioned commands
  create_view "view_example", version: 1
end
```

### 3. Methods are not available on regular migrations

There are no `create_view` or similar methods made available in regular `.rb` migrations. Such objects are expected to be created via versioned commands and `.sql`-based migrations.

### 4. Everything else works normally

This is the basis for upcoming features. All schema operations (like `rake db:schema:load`) will produce the expected outcome. Running `rake db:rollback` will either `DROP` the object(s) if on version 1, or execute the migration of the previous version.
