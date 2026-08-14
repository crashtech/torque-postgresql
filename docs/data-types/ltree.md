---
title: LTree
section: data-types
description: Reads PostgreSQL's ltree data type as an Array of labels and picks the right tree operator when querying it.
---

Reads PostgreSQL's `ltree` data type as an Array of labels and picks the right tree
operator when querying it. A label path is how you store a hierarchy in a single
column, which makes it a natural fit for categories, taxonomies and permissions.
[PostgreSQL Docs](https://www.postgresql.org/docs/current/ltree.html)

> **Note** `ltree` is an extension, so it has to be enabled before any of this
> works: `enable_extension 'ltree'` in a migration.

## How it works

A path is an Array of labels, so it flows through Ruby like any other list, and an
`ltree[]` column simply becomes an Array of Arrays. The value class adds the cheap
path operations on top, so comparing two loaded records never needs a round trip to
the database.

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
```

## Using it

The column is automatically identified and its value turned into a path.

```ruby
category.path            # => ["Top", "Science"]
category.path.to_s       # => "Top.Science"
category.path.depth      # => 2
category.path.root       # => ["Top"]
category.path.root?      # => false
category.path.parent     # => ["Top"]
category.path / 'Astro'  # => ["Top", "Science", "Astro"]
category.path.lca(other) # The longest common ancestor
category.path.index_of('Science')
```

Two paths can be compared without touching the database. Both checks include the
path itself, exactly like the `@>` and `<@` operators.

```ruby
a.ancestor_of?(b)   # Or a.covers?(b)
a.descendant_of?(b) # Or a.covered_by?(b)
```

The value can be set as a string, an array or symbols:

```ruby
category.path = 'Top.Science'
category.path = %w[Top Science]
category.path = [:Top, :Science]
```

Labels are limited to letters, numbers, underscores and dashes, and anything else
raises an `ArgumentError` rather than reaching the database as a syntax error.
Dashes are only accepted as of PostgreSQL 16, which is what
[`ltree.sanitize`]({{ site.baseurl }}/getting-started/configuring/#ltree.sanitize)
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
> [`ltree.sanitize`]({{ site.baseurl }}/getting-started/configuring/#ltree.sanitize)
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
Category.where(path: [category, :any])
                                    # Everything below it
category_path.ancestor_of?(other)   # And while comparing two paths
```

It takes precedence over the primary key, so a record that defines the method
describes itself rather than being reduced to its id. When the method describes a
pattern instead of a path, the condition becomes a `~` match on its own:

```ruby
Category.where(path: something)     # path ~ 'app.*' when to_tree_path says so
```

The method name comes from
[`ltree.compatible_method`]({{ site.baseurl }}/getting-started/configuring/#ltree.compatible_method),
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

> **Note** Patterns are only ever built, never parsed back. A pattern read from an
> `lquery` column keeps its text form untouched, and there is no Ruby object model
> describing its parts.

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

> **Note** On a path column `where(path: [a, b])` is **not** an `IN`. An Array is
> always a single value here: at the top level it is the sequence of items, and
> nested it is a group of alternatives. To test a path against several whole
> patterns, use the `?` operator below.

### Operators

The remaining operators are [Arel]({{ site.baseurl }}/querying/arel/) attribute
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
[`ltree.sanitize`]({{ site.baseurl }}/getting-started/configuring/#ltree.sanitize)
to normalize them before they are validated:

```ruby
Torque::PostgreSQL.configure do |config|
  config.ltree.sanitize = { '-' => '_' }
end

category.path = 'top.my-slug'  # Stored as top.my_slug
```

It applies to the labels the application provides, including the labels inside a
pattern, and never to values read from the database.
