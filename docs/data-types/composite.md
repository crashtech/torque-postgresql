---
title: Composite Types
section: data-types
description: >-
  Use any user-defined PostgreSQL composite type as a column, cast, tracked,
  validated and queried as regular attributes of an ActiveModel class.
---

Composite types manager. It allows any user-defined composite type to be used as a column, so that its contents are declared by the database, and then cast, tracked, validated, and queried as regular attributes of an ActiveModel class. The type is the single source of truth, which means the class describing it is optional, and the columns of the type become the attributes of the class. [PostgreSQL Docs](https://www.postgresql.org/docs/current/rowtypes.html)

## How it works

A composite type is a named row type, and it is made of columns, exactly like a table. The gem loads those types from the database, backs each of them with a class, and then any column using one of them returns an instance of that class.

## Migration

Composite types are created with `create_composite_type`, which uses the very same DSL as `create_table`, although limited to what a type supports.
```ruby
create_composite_type :address do |t|
  t.string  'street'
  t.string  'city'
  t.integer 'number'
  t.enum    'category', enum_type: :types
end

create_composite_type :full_address do |t|
  t.composite 'base', composite_type: :address   # Types can be nested
  t.string    'country'
end
```

Only the options that describe the type of a column are accepted, which are `limit`, `precision`, `scale`, `array`, `enum_type`, and `composite_type`. Anything else, like `null` or `default`, raises an `ArgumentError`, and so do indexes, because a type cannot hold either.

Existing types are changed with `change_composite_type`, which mirrors `change_table`.
```ruby
change_composite_type :address do |t|
  t.string 'zipcode'                             # ADD ATTRIBUTE
  t.change 'number', :bigint                     # ALTER ATTRIBUTE
  t.remove 'city'                                # DROP ATTRIBUTE
  t.rename 'street', 'road'                      # RENAME ATTRIBUTE
end
```

Just like `change_table`, it is not reversible. Use the single-column methods for migrations that have to be, where only `remove_composite_column` needs the type to be informed so that it can be inverted.
```ruby
add_composite_column    :address, 'zipcode', :string
remove_composite_column :address, 'zipcode', :string
change_composite_column :address, 'number', :bigint    # Not reversible
rename_composite_column :address, 'street', 'road'
```

Types are dropped with `drop_type`, and `create_composite_type` accepts `force: :cascade` to recreate one.
```ruby
drop_type :address, force: :cascade
create_composite_type :address, force: :cascade do |t|
  # ...
end
```

> **Note** All of these accept a `schema` option, and the schema dump writes the types before the tables that use them, always sorted so that a type comes after the ones it depends on.

## Columns

Once a type exists, any column can use it. Both the helper and the plain type name work.
```ruby
create_table :places do |t|
  t.string    :name
  t.composite :home, composite_type: :address                 # A single value
  t.composite :offices, composite_type: :address, array: true # A native array of values
  t.composite :location, composite_type: :full_address        # A nested type
  t.column    :other, :address                                # The type name works as well
end
```

## The composite Class

There is nothing to declare. Classes are created on demand under the namespace defined by [`composite.namespace`](/postgresql/getting-started/configuring/#composite.namespace), and their attributes come from the columns of the type.
```ruby
Composite::Address                          # Created on demand
Composite::Address.type_name                # 'address'
Composite::Address.columns.keys             # ['street', 'city', 'number', 'category']
Composite::Address.attribute_names          # ['street', 'city', 'number', 'category']
```

Write the class yourself when you want to add behavior to it. It inherits from `Torque::PostgreSQL::Composite`, and validations are available as any other ActiveModel class.
```ruby
# models/composite/address.rb
class Composite::Address < Torque::PostgreSQL::Composite
  validates :street, presence: true

  def to_s
    [street, number, city].compact.join(', ')
  end
end
```

Columns that the class declares on its own are respected, and only the ones it does not declare are loaded from the type.
```ruby
class Composite::Address < Torque::PostgreSQL::Composite
  attribute :number, :string    # Kept as a String, even though the type says integer
end
```

Use [`composite.irregular_types`](/postgresql/getting-started/configuring/#composite.irregular_types) when the name of the class does not match the name of the type.
```ruby
c.composite.irregular_types = { 'address' => 'Places::Location' }
```

## Records

The column simply returns an instance of the class, and a `Hash`, an `Array` of values, or an instance can be assigned to it.
```ruby
place = Place.new

place.home = { street: 'Main', number: 9 }      # A Hash is cast into an instance
place.home = Composite::Address.new(street: 'Main')
place.home = ['Main', 'Springfield', 9, 'A']    # Positional, in the order of the columns

place.home.street                               # 'Main'
place.home.number                               # 9, cast by the type of the column
place.home.to_h                                 # {street: 'Main', city: nil, ...}
```

Nested types and arrays of values behave the same way, and every entry is cast.
```ruby
place.location = { base: { street: 'Deep' }, country: 'BR' }
place.location.base                             # An instance of Composite::Address

place.offices = [{ street: 'A' }, Composite::Address.new(street: 'B')]
place.offices.first.street                      # 'A'
```

## Null

A column that is `NULL` reads back as `nil`, and it stays `NULL` until something is assigned to it.
```ruby
place = Place.create!(name: 'HQ')
place.home                                      # nil
place.home.blank?                               # true
# home IS NULL
```

A composite always carries every one of its columns, so a value with nothing set is a row of nulls, which PostgreSQL keeps apart from a null column. That is why an instance is never blank.
```ruby
place.home = {}
place.save!
# home => (,,,)

place.home.blank?                               # false, it is a value
```

## Querying

Whole values are compared as records, which keeps them able to use an index.
```ruby
Place.where(home: address)
# WHERE "places"."home" = '("Main",,"9",)'::address
```

A `Hash` is broken down into conditions over each column, and every pair goes back through the predicate builder, so the whole `where` vocabulary is available inside a composite.
```ruby
Place.where(home: { street: 'Main' })
# WHERE ("places"."home")."street" = 'Main'

Place.where(home: { number: 1..5 })
# WHERE ("places"."home")."number" BETWEEN 1 AND 5

Place.where(home: { street: %w[A B] })
# WHERE ("places"."home")."street" IN ('A', 'B')

Place.where(location: { base: { street: 'X' } })
# WHERE (("places"."location")."base")."street" = 'X'
```

A list of whole values asks whether any of them is the stored one.
```ruby
Place.where(home: [address, other])
# WHERE "places"."home" IN ('("Main",,"9",)'::address, '("Side",,"1",)'::address)
```

For array columns, a whole value checks whether any entry matches it, while a `Hash` checks whether any entry matches the columns it describes.
```ruby
Place.where(offices: address)
# WHERE '("Main",,"9",)'::address = ANY("places"."offices")

Place.where(offices: [address, other])
# WHERE "places"."offices" && '{"(...)","(...)"}'::address[]

Place.where(offices: { street: 'Main' })
# WHERE EXISTS (
#   SELECT 1 FROM UNNEST("places"."offices") "address"
#   WHERE ("address")."street" = 'Main'
# )
```

> **Note** A key that is not a column of the type raises an `ArgumentError`, instead of being silently ignored.

### Sorting and grouping

The same `Hash` reaches a column wherever Rails takes one, so `order`, `group`, `pluck` and `having` work over the value as well.
```ruby
Place.order(home: { street: :desc })
# ORDER BY ("places"."home")."street" DESC

Place.group(home: :street).count
# GROUP BY ("places"."home")."street"  => {"Main" => 1, "Side" => 1}

Place.group(:home).having(home: { street: 'Main' })
# HAVING (("places"."home")."street" = 'Main')

Place.pluck(home: :number)                      # [9, 1]
Place.order(:home)                              # The whole value, compared column by column
```

The gem's own [`distinct_on`](/postgresql/querying/distinct-on/), [`buckets`](/postgresql/querying/buckets/), [`join_series`](/postgresql/querying/join-series/) and the `Hash` form of calculations resolve a column the same way.
```ruby
Place.distinct_on(home: :street)
Place.join_series(1..10, with: { home: :number })
```

> **Note** Rails resolves one level when sorting and grouping, so a column of a nested type is only reachable in `where`. Array columns are not resolved this way, and `having` follows PostgreSQL's rule that the column has to be grouped or aggregated.

## Validations

Validations declared on the composite class run whenever the record is validated. A single `:invalid` error is added to the column, and every entry is validated for array columns.
```ruby
place.home.street = nil
place.valid?                                    # false
place.errors.added?(:home, :invalid)            # true
```

This is done with the `nested` validator, which is available for any attribute that holds objects that can validate themselves.
```ruby
validates :home, nested: true
validates :settings, nested: true, allow_blank: true
```

## Encryption

Individual columns can be encrypted, so that their values are stored encrypted inside the record, while the rest of it remains readable. This is Active Record's own `encrypts`, so all of its options are available.
```ruby
class Composite::Address < Torque::PostgreSQL::Composite
  encrypts :street
  encrypts :city, deterministic: true           # Same content produces the same ciphertext
end

# home => ("{""p"":""5nQ=="",""h"":{...}}",,9,)
place.home.street                               # 'Main'
place.home.ciphertext_for(:street)              # The stored ciphertext
```

> **Note** Encrypting a column that the type does not have raises an `ArgumentError`.

## Other Active Record features

Composite classes are ActiveModel classes with the parts of Active Record that make sense off a table, so several of the macros you already use are available inside them.

`enum` works as it does on a model, on top of the type that came from the database, except that everything which needs a relation or a persisted record is left out. Only the predicates are generated, so there are no `alpha!` bang methods and no scopes.
```ruby
class Composite::Address < Torque::PostgreSQL::Composite
  enum :category, { residential: 'A', commercial: 'B' }
end

place.home.category                             # 'residential'
place.home.residential?                         # true
Composite::Address.categories                   # {"residential" => "A", "commercial" => "B"}
```

`normalizes`, `store_accessor`, validations, callbacks, and `as_json` / `to_json` are available as well, and serialization only ever exposes the columns.
```ruby
place.home.as_json                              # {"street" => "Main", "city" => nil, ...}
```

> **Note** Anything that depends on a record being saved is out of reach, which means enum scopes, `value!` methods, and the `saved_change_to_*` family of `store_accessor` are not defined.

## Changes

Everything is tracked as any other attribute of the record, and reading a value never marks a record as changed.
```ruby
place.home = { street: 'Other' }
place.changed?                                  # true
```

The instance exposes its own changes as well.
```ruby
place.home.street_changed?                      # true
place.home.changes                              # {'street' => ['Main', 'Other']}
```
