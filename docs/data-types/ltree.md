---
title: LTree
section: data-types
description: Reads PostgreSQL's ltree data type as a path of labels and picks the right tree operator when querying it.
---

Reads PostgreSQL's `ltree` data type as a path of labels and picks the right tree
operator when querying it. A label path is how you store a hierarchy in a single
column, which makes it a natural fit for categories, taxonomies and permissions.
[PostgreSQL Docs](https://www.postgresql.org/docs/current/ltree.html)

> **Note** `ltree` is an extension, so it has to be enabled before any of this
> works: `enable_extension 'ltree'` in a migration.

## How it works

A path holds its labels as a plain list, so it enumerates like any other Array and
compares equal to one, and an `ltree[]` column simply becomes an Array of paths. The
value class adds the cheap path operations on top, so comparing two loaded records
never needs a round trip to the database.

Patterns work the same way: an `lquery` holds its items in the form you write them
in Ruby, and reads back from the database in that same form.

Conditions are not a plain `=`. The value decides: a plain path is compared with
`=`, and anything carrying an lquery feature is matched with `~`.

## Migration

Use `ltree` as the type of the column, with `array: true` for a list of paths.
Tree operators are only indexed by GiST.

```ruby
enable_extension 'ltree'

create_table "categories" do |t|
  t.string "title"
  t.ltree  "path", index: { using: :gist }
end

create_table "users" do |t|
  t.ltree "permissions", array: true
end
```

There is also `lquery`, for the rare case of storing a pattern in a column.

```ruby
add_column :rules, :pattern, :lquery
add_column :rules, :patterns, :lquery, array: true
```

## Using it

The column is automatically identified and its value turned into a path.

```ruby
category.path.items      # => ["Top", "Science"]
category.path.to_s       # => "Top.Science"
category.path.depth      # => 2
category.path.root       # => The path "Top"
category.path.root?      # => false
category.path.parent     # => The path "Top"
category.path / 'Astro'  # => The path "Top.Science.Astro"
category.path.lca(other) # The longest common ancestor
category.path.index_of('Science')
```

It is Enumerable over its labels and compares equal to a plain Array of them.

```ruby
category.path.map(&:downcase)      # => ["top", "science"]
category.path == %w[Top Science]   # => true
```

Two paths can be compared without touching the database. Both checks include the
path itself, exactly like the `@>` and `<@` operators.

```ruby
a.ancestor_of?(b)   # Or a.covers?(b)
a.descendant_of?(b) # Or a.covered_by?(b)
```

The value can be set as a string, or as an array of strings or symbols:

```ruby
category.path = 'Top.Science'
category.path = %w[Top Science]
category.path = [:Top, :Science]
```

Nothing is validated on the Ruby side. Whatever cannot be a label reaches PostgreSQL
as it is and fails there, as a syntax error. Dashes are only accepted as of
PostgreSQL 16, which is what
[`ltree.sanitize`](/postgresql/getting-started/configuring/#ltree.sanitize)
is for.

## Paths made of records

A tree is usually built out of the records themselves, so a record stands for the
value of its primary key wherever a label is accepted.

```ruby
category.path = [parent, child]      # Stored as "1.2"
category.path = ['app', parent]      # Records and labels mix freely
category.path / child                # Extending a path
```

That covers every operation, not just assignment, so the comparisons, `lca`,
`index_of`, the patterns and the conditions all take records too.

```ruby
parent_path.ancestor_of?(child)
category.path.index_of(child)

Category.where(path: [parent, child])  # path = '1.2'
Category.where(path: [parent, :any])   # path ~ '1.*'
Category.where(path: parent)           # path = '1'
```

It reads the primary key through `id`, so a model with a custom primary key uses
that column instead. A record that has not been saved yet, or one with a composite
primary key, raises an `ArgumentError` rather than producing a broken path.

> **Note** A UUID primary key contains dashes, which PostgreSQL only accepts in a
> label as of version 16. On anything older, set
> [`ltree.sanitize`](/postgresql/getting-started/configuring/#ltree.sanitize)
> to `{ '-' => '_' }`.

## Objects that describe their own path

Any object that responds to `to_tree_path` is asked for its own path, which is the
way to decide what a class means as a path instead of relying on its primary key.
The method can return a string, an array of labels, or another path.

```ruby
class Category < ActiveRecord::Base
  def to_tree_path
    [parent&.to_tree_path, id].compact
  end
end

document.path = category            # The path the category describes
Category.where(path: category)      # Same, as a condition
Category.where(path: [category, :any])  # Everything below it
category_path.ancestor_of?(other)   # And while comparing two paths
```

It takes precedence over the primary key, so a record that defines the method
describes itself rather than being reduced to its id. When the method describes a
pattern instead of a path, the condition becomes a `~` match on its own:

```ruby
Category.where(path: something)     # path ~ 'app.*' when to_tree_path says so
```

The method name comes from
[`ltree.compatible_method`](/postgresql/getting-started/configuring/#ltree.compatible_method),
and setting it to `nil` turns the behavior off.

## Patterns

An `lquery` is a pattern that matches paths. It is built from Ruby, one entry per
item of the pattern.

| PostgreSQL | Ruby | Meaning |
|---|---|---|
| `Top` | `'Top'` or `:Top` | A literal label |
| `*` | `:any` | Zero or more labels |
| `*{2}` | `2..2` | Exactly 2 labels |
| `*{0,2}` | `0..2` | Between 0 and 2 labels |
| `*{1,}` | `1..` | At least 1 label |
| `*{,3}` | `..3` | At most 3 labels |
| `sport*` | `'sport*'` | Prefix match |
| `sport@` | `'sport@'` | Case-insensitive |
| `sport%` | `'sport%'` | Matches initial underscore-separated words |
| `sport*@` | `'sport*@'` | Modifiers combine |
| `football\|tennis` | `%w[football tennis]` | Alternatives |
| `!football\|tennis` | `'!football\|tennis'` | A negated group |
| `football{1,}` | `'football{1,}'` | A quantified item |

Two rules cover the structure: a `Range` is a quantified star, and a nested `Array`
is a group of alternatives. Everything else is written on the string exactly as it
appears in SQL. The example from the PostgreSQL manual:

```ruby
['Top', 0..2, 'sport*@', '!football|tennis{1,}', %w[Russ* Spain]]
# => Top.*{0,2}.sport*@.!football|tennis{1,}.Russ*|Spain
```

A pattern holds those items exactly as written, and a pattern read from an `lquery`
column comes back in the same form, so a stored `users.*` is `['users', :any]`
again. A negated group and a quantified item have no Ruby form of their own, so they
stay Strings both ways.

```ruby
rule.pattern = ['users', :any]
rule.reload.pattern.items   # => ["users", :any]
rule.pattern.to_s           # => "users.*"
```

## Querying

A value without any pattern feature is a plain path, so it is compared with `=` and
`find_by`, uniqueness validations and associations keep working as usual. As soon as
the value carries a pattern feature, the condition becomes a `~` match.

```ruby
Category.where(path: 'Top.Science')     # path = 'Top.Science'
Category.where(path: %w[Top Science])   # path = 'Top.Science'

Category.where(path: ['Top', :any])     # path ~ 'Top.*'
Category.where(path: ['Top', 1..])      # path ~ 'Top.*{1,}'
Category.where(path: ['Top', %w[a b]])  # path ~ 'Top.a|b'
Category.where(path: 'Top.*.sport*@')   # path ~ 'Top.*.sport*@'
```

A star matches zero labels too, which means `Top.*` matches `Top` itself and is
exactly the same as `<@ 'Top'`. GiST indexes both, so the whole subtree query is
just a pattern. Use `*{1,}` when the path itself should be left out.

### Lists of values

An Array is one path or one pattern, unless its first entry is itself an Array, a
path or a pattern. Then it is a list of values, and the condition asks whether any of
them matches: paths become an `IN`, patterns go through the `?` operator.

```ruby
Category.where(path: [%w[Top a], %w[Top b]])            # path IN ('Top.a', 'Top.b')
Category.where(path: [['Top', :any], ['Other', 1..]])   # path ? '{Top.*,Other.*{1,}}'::lquery[]
Category.where(path: [LTree['Top'], 'Other'])            # path IN ('Top', 'Other')
```

> **Note** A group of alternatives as the very first item of a pattern has to be
> written as a string, `['a|b', :any]`, since a leading Array turns the value into a
> list.

### Array columns

On an `ltree[]` column a single value asks whether any entry matches it, and a list
whether any entry matches any of them.

```ruby
User.where(permissions: 'app.users')                      # 'app.users' = ANY(permissions)
User.where(permissions: ['app', :any])                    # permissions ~ 'app.*'
User.where(permissions: [%w[app a], %w[app b]])           # permissions && '{app.a,app.b}'
User.where(permissions: [['app', :any], ['x', :any]])     # permissions ? '{app.*,x.*}'::lquery[]
User.where(permissions: [])                               # CARDINALITY(permissions) = 0
```

### Pattern columns

An `lquery` column mirrors the path column: a pattern is the equality and a path is
the match, meaning which of the stored patterns match that path. PostgreSQL defines
no equality operator for `lquery`, so the equality happens over the text form.

```ruby
Rule.where(pattern: ['users', :any])                      # pattern::text = 'users.*'
Rule.where(pattern: 'users.admin')                        # pattern ~ 'users.admin'::ltree
Rule.where(pattern: [%w[users admin], %w[posts new]])     # pattern ~ ANY('{users.admin,posts.new}'::ltree[])
Rule.where(patterns: 'users.admin')                       # 'users.admin'::ltree ~ ANY(patterns)
```

Every value given to one of these columns goes through this handler. `nil` is still
`IS NULL`, but a Relation or an Arel attribute is not accepted as a value here.

### Operators

The remaining operators are [Arel](/postgresql/querying/arel/) attribute
methods, and PostgreSQL defines all of them for `ltree[]` columns as well, where
they mean that *some* entry of the array matches.

```ruby
path = Category.arel_table['path']

path.contains(value)            # path @> ?  Is it an ancestor of the value
path.contained_by(value)        # path <@ ?  Is it a descendant of the value
path.matches_lquery(value)      # path ~  ?  Does it match the pattern
path.matches_any_lquery(value)  # path ?  ?  Does it match any of the patterns
```

## Testing

Labels that come from somewhere else rarely satisfy PostgreSQL's rules on their own,
and a slug with dashes only works as of PostgreSQL 16. Set
[`ltree.sanitize`](/postgresql/getting-started/configuring/#ltree.sanitize)
to normalize them before they are sent:

```ruby
Torque::PostgreSQL.configure do |config|
  config.ltree.sanitize = { '-' => '_' }
end

category.path = 'top.my-slug'  # Stored as top.my_slug
```

It applies to the labels the application provides, including the labels inside a
pattern, and never to values read from the database.
