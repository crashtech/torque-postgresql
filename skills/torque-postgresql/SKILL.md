---
name: torque-postgresql
description: PostgreSQL features in Rails through the torque-postgresql gem. Use when writing models, migrations, or queries in an app whose Gemfile has torque-postgresql, or when a task needs a PostgreSQL type (enum, enum set, jsonb document, composite, ltree, range, interval, geometry) or query feature (CTE, DISTINCT ON, FILTER aggregates, width_bucket, generate_series, full-text search, array associations, table inheritance).
---

# torque-postgresql

The gem exposes PostgreSQL features through the regular Rails DSL: migration methods that dump
to `schema.rb`, model macros, and relation methods. Reach for it before raw SQL.

## Steps

1. Locate the installed gem with `bundle info torque-postgresql`. Done when you know its version
   and path.
2. Read the app's `Torque::PostgreSQL.configure` block (search `config/` for it). Done when you
   know which features are off and which macros are renamed: every `base_method` key renames a
   macro, and `versioned_commands` and `cross_join` stay off unless enabled there.
3. Pick the feature from the table below and read its docs page before writing code. Done when
   the migration, the model macro, and the query you plan all appear on that page.
4. Check exact signatures in `<gem path>/sig/`, when the installed release ships one. Methods
   generated per attribute (`admin?`, period scopes, `full_text_search`) are named on the docs
   page, never in `sig/`.
5. Write the migration with the gem's DSL, run it, and confirm `db/schema.rb` dumps it.

## Features

Docs live at `https://torque.dev/postgresql/<page>/`. The index is
`https://torque.dev/postgresql/llms.txt`, and every page in one file is
`https://torque.dev/postgresql/llms-full.txt`.

| Need | Migration | Model or query | Page |
|---|---|---|---|
| Fixed list of values | `create_enum`, `t.enum enum_type:` | `torque_enum :role`, `Enum::Roles` | `data-types/enum` |
| Several values of one enum | `t.enum enum_type:, array: true` | `torque_enum_set :perms` | `data-types/enum-set` |
| Typed jsonb document | `t.jsonb` | `struct_for :settings, Klass` | `data-types/struct` |
| Database composite type | `create_composite_type`, `t.composite composite_type:` | `Composite::Address` | `data-types/composite` |
| Tree paths | `enable_extension 'ltree'`, `t.ltree`, `t.lquery` | `where(path: ...)` | `data-types/ltree` |
| Time windows | `t.tsrange`, `t.daterange` | `period_for :period` | `data-types/date-time-range` |
| Durations | `t.interval` | `ActiveSupport::Duration` values | `data-types/interval` |
| Geometry | `t.box`, `t.circle`, `t.line`, `t.segment` | value objects | `data-types/box` and siblings |
| Array of foreign keys | `t.bigint :tag_ids, array: true` | `belongs_to_many :tags`, `has_many :videos, array: true` | `modeling/belongs-to-many`, `modeling/has-many` |
| Table inheritance | `create_table :child, inherits: :parent` | `expand_records` | `modeling/inherited-tables` |
| Value computed on demand | | `dynamic_attribute(:name) { }` | `modeling/dynamic-attributes` |
| Conditional upsert | | `upsert_all(rows, where: ...)` | `modeling/insert-all` |
| CTE | | `auxiliary_statement :name`, `.with(:name)` | `querying/auxiliary-statements` |
| First row per group | | `distinct_on(:col)` | `querying/distinct-on` |
| Histogram | | `buckets(:col, range_or_list)` | `querying/buckets` |
| Several filtered aggregates | | `segments(name: condition).count` | `querying/segments` |
| Report rows with no data | | `join_series(range, with: :col)` | `querying/join-series` |
| Full-text search | `t.search_vector columns:` | `torque_search_for :col`, `.full_text_search` | `querying/full-text-search` |
| Regexp and array conditions | | `where(title: /x/)` | `querying/predicate-builder` |
| SQL functions and operators | | `FN.*`, Arel infix methods | `querying/arel` |
| Several schemas | `create_schema` | `self.schema =` | `experimental/multiple-schemas` |
| Versioned views, functions, triggers, types | `rails g torque:view` and siblings | | `experimental/versioned-commands` |
| Join a function, subquery, or row list | | `cross_join(source, as:)` | `experimental/cross-join` |

## Rules

- **Enum types** come from Rails' own `create_enum`. Adding values with `add_enum_values` may
  need `disable_ddl_transaction!` in that migration.
- **Struct classes** subclass `Torque::PostgreSQL::Struct` and are strict by default. Only `jsonb`
  columns can be queried by property. Encrypt properties, never the whole column.
- **Inherited records** reached through an association come back partial and read-only. Load
  them with `expand_records` before writing to them.
- **ltree labels** accept dashes only on PostgreSQL 16+. The `ltree.sanitize` setting rewrites
  them, which matters for UUID labels.
- **`FN`** is `Torque::PostgreSQL::FN`. The app may expose it under a shorter name through
  `arel.expose_function_helper_on`, which the docs write as `PG::Fn`.
- **Array conditions** use `ANY` and overlaps only when `predicate_builder.handle_array_attributes`
  is on. It is off by default.
