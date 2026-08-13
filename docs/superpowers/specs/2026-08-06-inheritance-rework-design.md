# Table Inheritance Rework — Design

Date: 2026-08-06
Branch: `feature/inheritance-rework`
Status: implemented

## Motivation

Physical (PostgreSQL `INHERITS`) inheritance currently gives the wrong class by
default. `Activity.all` returns `Activity` instances even for rows that live in
`activity_books`, so a subclass that overrides a parent method is silently
bypassed. That is the opposite of the STI guarantee, where the model is always
the correct one.

Two consequences drive this rework:

1. **Correctness.** Method overrides on subclasses do not run, because querying
   never produces the subclass.
2. **Associations.** Getting correct classes through an association is painful
   today: `cast_records` is a relation-level opt-in that does not propagate
   through `includes`, so association targets are always base-class instances.

Getting the right class today costs two extra queries per record: the
`dynamic_attribute(_record_class)` in `base.rb:41-47` plucks `tableoid` for a
single record, and `cast_record` then re-queries via `klass.find(self.id)`
(`inheritance.rb:20`, marked `:TODO:` on the line above).

### Target behavior

```ruby
# Always the correct class, with no opt-in:
Author.includes(:activities).first.activities.first.class  # => ActivityBook

# ...but only base-table columns are loaded, so the record is partial:
record.partial_record?  # => true
record.readonly?        # => true
record.url              # => ActiveModel::MissingAttributeError

# Opt in to full, editable records — one query per table:
Author.includes(:activities).merge(Activity.expand_records)
```

## Scope

In scope:

- Always instantiate the correct class for physically inherited rows.
- Partial records: read-only, `partial_record?`, `MissingAttributeError` on
  un-loaded columns, `reload` upgrades to full and editable.
- `expand_records` replacing `cast_records`, with a per-table query strategy by
  default and the existing JOIN strategy behind `eager_load: true`.
- Propagating expansion through `includes` + `merge`.
- Removing `_auto_cast`; making `_record_class` internal.
- Resetting and thread-safely initializing the inheritance class-level caches.

Explicitly out of scope:

- `lookup_model` and the schema-cache model resolution mechanism stay exactly as
  they are. They are correctly tied to the schema cache.
- No changes to the DDL layer (`create_table(inherits:)`) or schema dumping.
- `itself_only` keeps its current behavior.

## Architecture

| Unit | Responsibility | File |
|---|---|---|
| `Relation::Inheritance` | discriminator injection, `itself_only`, `expand_records` values, conflict guard, `exec_queries` hook | `lib/torque/postgresql/relation/inheritance.rb` (exists) |
| `Inheritance::Expander` | group partials, build column-limited queries, merge attribute sets | `lib/torque/postgresql/inheritance/expander.rb` (new) |
| `Inheritance` | class resolution, partial instantiation, cached class-level metadata | `lib/torque/postgresql/inheritance.rb` (exists) |
| `Inheritance::Record` | `partial_record?`, partial-state transitions, `reload` override | `lib/torque/postgresql/inheritance/record.rb` (new) |
| `Relation::Merger` | carry `expand_records` values across `merge` | `lib/torque/postgresql/relation/merger.rb` (exists) |
| `Relation` (`preload_associations`) | expand preloaded association targets for merged expand values | `lib/torque/postgresql/relation/inheritance.rb` (exists) |

The expander is a separate unit so it can be tested against an array of records
without issuing the base query.

## Discriminator injection

In the existing `build_arel` of `Relation::Inheritance`, add
`arel_table['tableoid'].pg_cast(:regclass).as('_record_class')` to
`select_extra_values` when `model.physically_inheritances?` is true and
`itself_only_value` is not set.

This reuses `relation.rb:98` — `arel.project(*select_extra_values) if
select_values.blank?` — which yields two behaviors without extra work:

- An explicit `select` is never polluted.
- Calculations (`count`, `sum`) do not receive the extra column.

`itself_only` must not add the discriminator: `FROM ONLY` guarantees every row
belongs to the base table, so there is nothing to discriminate.

Resulting SQL for a hierarchy parent:

```sql
SELECT "activities".*, "activities"."tableoid"::regclass AS _record_class
FROM "activities"
```

## Class-level metadata

A new memoized method, following the existing `inheritance_*` naming
convention, identifies dependents that actually add columns:

```ruby
def inheritance_expandable_dependents
  @inheritance_expandable_dependents ||= casted_dependents.select do |_table, klass|
    (klass.attribute_names - attribute_names).any?
  end.freeze
end
```

A child table with no additional columns is fully represented by the parent's
row. Such a record is **not** partial and stays editable. This set is used in
two places: deciding whether to mark a record partial, and choosing default
`expand_records` targets (so a column-less child never triggers a query).

### Cache reset and thread safety

These class-level caches are schema-derived and currently never reset, which is
why specs poke ivars directly (`table_inheritance_spec.rb:198` and `:406`):

- `@physically_inherited`
- `@casted_dependents`
- `@inheritance_merged_attributes`
- `@inheritance_mergeable_attributes`
- `@inheritance_expandable_dependents` (new)

Override the protected `reload_schema_from_cache` (`model_schema.rb:553-571`)
to nil all five, then call `super`. That single hook covers every reset path AR
already has: `reset_column_information` (`:528`), a failed `load_schema`
(`:543`), and `inherited` (`:577`), including recursion into subclasses.

Initialization of each cache is wrapped in the existing
`@load_schema_monitor` (`model_schema.rb:549-550`) using the same
double-checked-locking shape as AR's `load_schema` (`:534-546`): check, then
synchronize, then check again. The monitor is reentrant, so nested builders
(`inheritance_expandable_dependents` calling `casted_dependents`) cannot
deadlock.

## Instantiation

`instantiate_instance_of` becomes substantially simpler:

```ruby
def instantiate_instance_of(klass, attributes, types = {}, &block)
  return super unless klass.physically_inheritances?

  record_class = attributes['_record_class']
  return super if record_class.blank? || record_class == klass.table_name

  real_class = klass.casted_dependents[record_class]
  klass.raise_unable_to_cast(record_class) if real_class.nil?

  record = super(real_class, attributes.to_hash.except('_record_class'), types, &block)
  record.send(:mark_as_partial_record!) if klass.inheritance_expandable_dependents.key?(record_class)
  record
end
```

Notes:

- The `_auto_cast` check is gone. Casting is unconditional — that is the point
  of the rework.
- `sanitize_attributes` is rewritten to work on the plain hash from
  `IndexedRow#to_hash`, removing the `@row` / `@column_indexes` surgery
  entirely. One rule serves both paths: drop `_record_class`, unwrap prefixed
  keys matching the real class's table, keep unprefixed keys present in
  `real_class.attribute_names`, and discard the rest. The plain path has no
  prefixed keys, and the `eager_load: true` path uses the same rule to project
  out sibling tables' `table__column` aliases.
- `_record_class` is dropped from the row via `IndexedRow#to_hash`
  (`result.rb:60`), keeping it out of the `AttributeSet`. That is what makes
  `respond_to?(:_record_class)` false. It is readable today precisely because it
  sits in the attribute hash without a generated reader, so `method_missing`
  resolves it.

## Partial records

`Inheritance::Record` provides:

- `partial_record?` — reads `@partial_record`.
- `mark_as_partial_record!` (private) — sets `@partial_record = true` and calls
  `readonly!` (`core.rb:764`).
- `mark_as_full_record!` (private) — sets `@partial_record = false` and
  `@readonly = false`.

**Definition of partial:** instantiated as a subclass from an ancestor table's
row, where that subclass adds columns. A child that adds no columns is never
partial, regardless of how it was queried. This does not collide with
`select(:id)`, which is a different kind of incompleteness that AR already
handles.

The name is deliberately generic rather than inheritance-specific. A possible
future feature — independent of inheritance — would flag any narrowly-selected
record (`select(:id)`) as partial and likewise prevent changes. That is out of
scope here, but the naming should not have to change if it lands.

Behavior, all of which falls out of AR without custom code:

- Persisting raises `ActiveRecord::ReadOnlyRecord`, via `readonly!`.
- Reading an un-loaded child column raises
  `ActiveModel::MissingAttributeError`. Generated readers are codegen'd as
  `_read_attribute(name) { |n| missing_attribute(n, caller) }`
  (`attribute_methods/read.rb:18`); `klass.attribute_types` includes the child
  columns while the row does not supply them, so `Attribute::Uninitialized#value`
  yields and raises.

### `reload`

`reload` is the upgrade path; no separate `expand` method is added. AR's
`reload` already does the right thing structurally: `_find_record` goes through
`self.class`, which is now the correct subclass, so it queries
`activity_books` and returns the full row; it replaces `@attributes` wholesale
(`persistence.rb:753`) and nils the mutation trackers (`dirty.rb:63-68`).

It does **not** clear `@readonly`, so an override is required to call
`mark_as_full_record!` after `super`.

## Expansion

### API

```ruby
def expand_records(*models, eager_load: false, filter: false)
  spawn.expand_records!(*models, eager_load: eager_load, filter: filter)
end
```

Two relation values back this, alongside the existing `itself_only_value`:
`expand_records_values` (the target model list) and
`expand_records_eager_load_value` (the strategy flag).

- No arguments expands every entry in `inheritance_expandable_dependents`.
- Arguments limit which models expand. Unlisted models still get their correct
  class but remain partial and read-only. This differs from old
  `cast_records(ActivityBook)`, which returned plain `Activity` for unlisted
  types (`table_inheritance_spec.rb:374-381`).
- `filter: true` keeps the existing `cast_records` behavior of adding a
  `WHERE tableoid::regclass::varchar IN (...)` clause. It is independent of the
  strategy and applies to both.
- `eager_load: true` routes to the existing `build_inheritances` JOIN and
  `COALESCE` strategy, producing full records in a single query. Otherwise the
  arel is untouched beyond the discriminator.

`expand_records` and `itself_only` are mutually exclusive. Each raises
`InheritanceError` (the existing class, `inheritance.rb:5`) if the other is
already set, so misuse fails at the call site in both orders.

### The pass

Hooked on `exec_queries` in `Relation::Inheritance`:

```ruby
def exec_queries(&block)
  records = super
  return records if expand_records_values.empty? || expand_records_eager_load?

  Inheritance::Expander.new(model, records, expand_records_values).call
  records
end
```

`Inheritance::Expander#call`:

1. Select candidates: `records.select { |r| r.partial_record? && targets.include?(r.class) }`.
2. Group them by `r.class`. Grouping on the class is valid because the class is
   already correct at this point.
3. Per class:
   - `extra = klass.attribute_names - model.attribute_names`
   - `SELECT pk, *extra FROM child_table WHERE pk IN (ids)`, issued through
     `select_all` so it does not recurse back into instantiation.
   - Index the result rows by primary key.
4. Per record: build an `AttributeSet` containing only the extra columns, each
   built with `Attribute.from_database(name, raw, klass.attribute_types[name])`,
   then `record.instance_variable_get(:@attributes).reverse_merge!(set)`, then
   `record.send(:mark_as_full_record!)`.

Only tables with matching rows are queried, so an absent child costs nothing.

### Why dirty tracking is preserved

This is a hard requirement: expansion must not make records appear changed.

- `Attribute.from_database` (`attribute.rb:8`) produces a `FromDatabase`, whose
  `changed?` is `changed_from_assignment? || changed_in_place?`. Both are false
  for an unread value with no `original_attribute`.
- The merge mutates the `AttributeSet` **in place**, so the memoized
  `AttributeMutationTracker` still references the same object. No tracker reset
  is needed and `record.changed?` stays `false`.
- Direction is correct: `reverse_merge!` is `other.merge(self)`
  (`attribute_set.rb:102-104`), so already-loaded base columns win and only
  missing extras are added.

The merge set is built explicitly rather than through
`attributes_builder.build_from_database`, because a `LazyAttributeSet` carries
`types` for *all* of the child's columns and `reverse_merge!` materializes it
via the protected `attributes` reader (`attribute_set/builder.rb:59-67`),
injecting `Attribute.uninitialized` entries for every column outside the narrow
`SELECT`. Harmless, but wasteful and less clear about intent.

## Propagating through `includes`

`Author.includes(:activities).merge(Activity.expand_records)` merges into the
**Author** relation, but the `:activities` preload builds its own scope from the
reflection (`preloader/association.rb:294`, consumed at `:53-55`) and does not
inherit the parent relation's values. This is the same reason
`includes(:x).merge(X.where(...))` does not filter a preload today. Without
explicit support the expand values would sit unused on the Author relation.

Injecting the values into the preload *scope* is not possible:
`Relation#preload_associations` (`relation.rb:1321-1328`) constructs the
`Preloader` with `scope: StrictLoadingScope || nil` and never passes the root
relation, so `Preloader::Association#build_scope` has no channel to read them
from. The only scope it merges is `preload_scope`, which is shared across every
association in the call and therefore cannot carry per-model targets.

Design:

1. `Relation::Merger` stores incoming expand values on the target relation keyed
   by the source relation's base model, alongside the existing
   `select_extra_values` merge (`merger.rb:24-25`). Values whose model matches
   the relation's own model continue to merge directly.
2. Override `Relation#preload_associations` to run the expansion pass over the
   preloaded association targets after `super`, for each stored entry whose
   model matches a preloaded association's `klass`.

This keeps the expander stateless and reuses it unchanged. Because the expander
batches across every owner's targets at once, it is still one query per table.

There are therefore two entry points into the expander — `exec_queries` for a
direct `expand_records` call, and `preload_associations` for values arriving via
`merge` — both delegating to the same unit.

### Query sequence

For `Author.includes(:activities).merge(Activity.expand_records)`:

1. `authors`
2. `activities` (with `_record_class`) — records initialized with correct
   classes, marked partial
3. `activity_books` — narrow select, matching records amended and unmarked
4. `activity_posts` — same
5. one query per further expandable child table present in the result

So the count is `2 + (expandable child tables actually present)`. Tables with no
matching rows, and children that add no columns, are skipped entirely.

## Error handling

| Case | Behavior | Source |
|---|---|---|
| `itself_only` + `expand_records` | `InheritanceError` at call time, both orders | existing class |
| Unresolvable `_record_class` | `InheritanceError` naming `irregular_models` | existing `raise_unable_to_cast` |
| Write to partial record | `ActiveRecord::ReadOnlyRecord` | free via `readonly!` |
| Read un-expanded column | `ActiveModel::MissingAttributeError` | free via codegen |
| Expansion finds no child row | record stays partial | new |

A child row can be missing if it is deleted between the base query and the
expansion query. Leaving the record partial is honest about what was loaded, and
read-only status prevents damage.

`raise_unable_to_cast` now fires on plain queries, so an inherited table with no
resolvable model breaks `Activity.all` where previously it only broke
`cast_records`. Because the schema cache resolves every data source when it is
built, hitting this at query time means the table appeared after the cache was
built — a race condition. Raising is the correct response, and no fallback is
designed for it. It belongs in the release notes as a new failure mode.

## Testing

Restructure `spec/tests/table_inheritance_spec.rb`.

Existing specs that must change:

- `:279` — `Activity.all.to_sql` now includes the discriminator.
- `:311-341` — the `cast_records` block becomes `expand_records(eager_load: true)`.
- `:392` — the `xit` becomes a real spec: neither `_record_class` nor
  `_auto_cast` responds.
- `:420-424` — `_record_class` readability spec is deleted.
- `:401-449` — the `cast_record` block becomes `reload`-upgrade specs.
- `:198` and `:406` — ivar-poking workarounds are removed, since cache reset now
  works.

Existing specs that must pass **unchanged**, as regression signal:

- `:285` — `itself_only` SQL, now a meaningful assertion that it carries no
  discriminator.
- `:343-361` — `count` and `sum` add no extra columns.
- `:430-448` — the UUID hierarchy.

New specs:

- Correct class with no opt-in, both from a plain query and through `includes`.
- `partial_record?` true for a child that adds columns; **false and editable**
  for a child that adds none.
- `ReadOnlyRecord` on persisting a partial record.
- `MissingAttributeError` on reading an un-expanded child column.
- `reload` upgrade: full attributes, `partial_record?` false, `readonly?` false,
  `changed?` false.
- **Expansion leaves records non-dirty** — `changed? == false` after the merge.
  This is the highest-value new spec, guarding the dirty-tracking requirement.
- Query counts for `Author.includes(:activities).merge(Activity.expand_records)`.
- Subset expansion: listed models full and editable, unlisted correct-class but
  partial.
- `expand_records` and `itself_only` raising in both orders.
- Cache reset: metadata recomputes after `reset_column_information`.

Coverage gap closed: nothing currently tests inheritance through associations,
which is the reported fragility. Three-level expansion is not separately tested —
it follows from the per-table strategy and lacks a realistic use case.

## Compatibility

Breaking. Requires a major version bump.

- `cast_records` / `cast_records!` removed; use `expand_records(eager_load: true)`.
- `_auto_cast` removed. `config.inheritance.auto_cast_column_name` becomes dead
  and is deleted.
- `_record_class` is no longer a readable attribute.
  `config.inheritance.record_class_column_name` still names the internal alias.
- `dynamic_attribute(_record_class)` lazy pluck in `base.rb:41-47` is removed.
- `inheritance_mergeable_attributes` and `sanitize_attributes` remain, used only
  by the `eager_load: true` path.
- `Activity.all` SQL changes.

The loudest break is the intended one: `Activity.first.update!(...)` now raises
`ReadOnlyRecord` when the row lives in a child table. That is the correctness fix
landing, and existing applications will feel it.
