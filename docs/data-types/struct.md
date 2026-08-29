---
title: Struct
section: data-types
description: Struct manager for documents.
---

Struct manager for documents. It allows any `json` or `jsonb` column to be backed by an ActiveModel class, so that the contents of the document are declared, typed, cast, validated, and tracked as regular attributes, while the column still holds plain JSON. A single class can back several columns and several models, and the document that is stored is always a 1-to-1 representation of the properties that were actually written to it. [PostgreSQL Docs](https://www.postgresql.org/docs/current/datatype-json.html)

## How it works

The struct class describes what the document can hold, and the column stores exactly what was written to it. A property that has never been written and has no default is not stored, which means the document never carries keys that were not asked for, and a document that has nothing in it is stored as `NULL`.

## Migration

Any `json` or `jsonb` column can back a struct, including arrays of them. There is nothing special to do in the migration.
```ruby
create_table :profiles do |t|
  t.string :name
  t.jsonb  :settings                # A single document
  t.json   :bio                     # json works exactly like jsonb
  t.jsonb  :previews                # A list of documents, inside one column
  t.jsonb  :snippets, array: true   # A native array of documents
end
```

> **Note** The column type is respected, so a `json[]` column is handled as `json[]`, and never silently turned into `jsonb`.

## The struct Class

Struct classes inherit from `Torque::PostgreSQL::Struct`, and they use the very same `attribute` method as any other ActiveModel class. Validations are available as well.
```ruby
# models/profile/settings.rb
class Profile::Settings < Torque::PostgreSQL::Struct
  attribute :theme, :string, default: 'light'
  attribute :notifications, :boolean, default: true
  attribute :tags

  validates :theme, inclusion: { in: %w[light dark] }, allow_nil: true
end
```

Instances behave like any other ActiveModel object, and they are compared by class and by the properties they hold.
```ruby
settings = Profile::Settings.new(theme: 'dark')

settings.theme                              # 'dark'
settings.attributes                         # {'theme' => 'dark', 'notifications' => true}
settings.theme_changed?                     # true
settings == Profile::Settings.new(theme: 'dark')
```

Any ActiveModel class that includes `ActiveModel::Attributes` is accepted too, and nothing is added to it. Those classes will not have the extra features described below, like plain access to unknown properties.

## Models

You have to go to each of your models and set up which columns are backed by which class. The method name is defined on [`struct.base_method`]({{ site.baseurl }}/getting-started/configuring/#struct.base_method).
```ruby
# models/profile.rb
class Profile < ActiveRecord::Base
  struct_for :settings, Settings
  struct_for :bio, 'Profile::Bio'   # A String or a Symbol is accepted as well
end
```

These are the available options:
```ruby
struct_for :settings, Settings, default: { theme: 'dark' }  # The default for new records
struct_for :previews, Preview, array: true                  # A list of documents
struct_for :settings, Settings, delegate: %i[theme]         # Reader and writer on the record
struct_for :settings, Settings, backfill: true              # Apply defaults to stored documents
struct_for :settings, Settings, strict: false               # Accept undeclared properties
```

From there on, the column simply returns an instance of the class.
```ruby
profile = Profile.new

profile.settings                 # An instance of Profile::Settings
profile.settings.theme = 'dark'
profile.settings.theme           # 'dark'

profile.settings = { theme: 'dark' }                    # A Hash is cast into an instance
profile.settings = Profile::Settings.new(theme: 'dark') # An instance is taken as it is
profile.settings = nil                                  # The column is set to NULL
```

## The document

A property is stored only when it was written to or when it has a default, which means the document mirrors the properties of the instance, and nothing else.
```ruby
profile = Profile.create!
# settings => {"theme": "light", "notifications": true}
# `tags` has no default, so it is not part of the document

profile.settings.tags = %w[one]
profile.save!
# settings => {"tags": ["one"], "theme": "light", "notifications": true}
```

The same rule applies when reading, so properties that are missing from a stored document are simply not set, regardless of the class having a default for them. This keeps records that were stored before a property existed exactly as they are, and it can be changed with [`backfill`](#backfill).
```ruby
# settings => {"tags": ["one"]}
profile.settings.theme           # nil, the document does not have it
profile.settings.tags            # ['one']

profile.settings.tags << 'two'
profile.save!
# settings => {"tags": ["one", "two"]}
```

A document that has nothing to store is stored as `NULL`, which means classes without any default keep their column `NULL` until something is written to them.
```ruby
class Profile::Bio < Torque::PostgreSQL::Struct
  attribute :headline, :string
end

profile = Profile.create!
profile.bio                      # An instance, with everything unset
# bio IS NULL

profile.bio.headline = 'Hello'
profile.save!
# bio => {"headline": "Hello"}
```

## Defaults

Class-level defaults belong to the class, and they are written to the database as soon as a record that has them is created, which also means such records are marked as changed.
```ruby
Profile.new.changed              # ['settings']
```

The `default` option adds to, or overrides, the class-level defaults for that column only. It accepts a `Hash`, a `Proc`, or a `Symbol`, and both the `Proc` and the `Symbol` are resolved on the record, so that defaults can be composed from it.
```ruby
class Profile < ActiveRecord::Base
  struct_for :settings, Settings, default: { theme: 'dark' }
  struct_for :settings, Settings, default: -> { { theme: dark_mode? ? 'dark' : 'light' } }
  struct_for :settings, Settings, default: :default_settings

  def default_settings
    { theme: dark_mode? ? 'dark' : 'light' }
  end
end
```

> **Note** Defaults are applied to new records only, just like a column default. Records that are already stored are not affected by a default that was added later.

## Backfill {#backfill}

Use `backfill` when properties that are missing from stored documents should be read at their class-level default. Records loaded that way are marked as changed, so that the next save writes the complete document.
```ruby
struct_for :settings, Settings, backfill: true          # All the defaults
struct_for :settings, Settings, backfill: %i[theme]     # Only the listed properties

# settings => {"tags": ["one"]}
profile.settings.theme           # 'light'
profile.changed?                 # true
profile.save!
# settings => {"tags": ["one"], "theme": "light", "notifications": true}
```

## Arrays

There are two ways of storing a list of documents, and both of them return a regular `Array` of instances. Use `array: true` for a JSON array stored inside a single column, and a native array column for the PostgreSQL array of documents. Both are cast, tracked, and validated per entry.
```ruby
class Profile < ActiveRecord::Base
  struct_for :previews, Preview, array: true    # jsonb  => [{...}, {...}]
  struct_for :snippets, Snippet                 # jsonb[] => {"{...}","{...}"}
end

profile.previews                                      # []
profile.previews << Profile::Preview.new(label: 'a')
profile.previews.first.label = 'b'                    # In-place changes are detected
profile.save!
```

## Nested documents

A property can be backed by another struct class, and the document it holds is stored as a document of its own, not as an encoded string.
```ruby
class Profile::Address < Torque::PostgreSQL::Struct
  attribute :city, :string
  attribute :zip, :integer
end

class Profile::Settings < Torque::PostgreSQL::Struct
  attribute :address, Torque::PostgreSQL::Adapter::OID::Struct.new(Profile::Address)
end

profile.settings.address = { city: 'SP', zip: 1 }
profile.settings.address                 # An instance of Profile::Address
# settings => {"address": {"city": "SP", "zip": 1}}
```

## Querying

A `Hash` is broken down into conditions over each property, and every pair goes back through the predicate builder, so the whole `where` vocabulary is available inside a document. Each property is cast to the type that the class declares for it.
```ruby
Profile.where(settings: { theme: 'dark' })
# WHERE ("profiles"."settings" #>> ARRAY['theme']) = 'dark'

Profile.where(settings: { notifications: true })
# WHERE ("profiles"."settings" #>> ARRAY['notifications'])::boolean = TRUE

Profile.where(settings: { theme: %w[light dark] })
# WHERE ("profiles"."settings" #>> ARRAY['theme']) IN ('light', 'dark')

Profile.where(settings: { address: { city: 'SP' } })
# WHERE ("profiles"."settings" #>> ARRAY['address', 'city']) = 'SP'
```

A `Hash` beneath a property that is not a document of its own is just a deeper path, read the way `jsonb` reads it, so an entry of an array is reached by its index. Nothing is cast down there, since no class describes it.
```ruby
Profile.where(settings: { tags: { 0 => 'test' } })
# WHERE ("profiles"."settings" #>> ARRAY['tags', '0']) = 'test'
```

A whole instance is still compared as a whole document, which means every property it holds has to match, and nothing else can be stored.
```ruby
Profile.where(settings: Profile::Settings.new(theme: 'dark'))
# WHERE "profiles"."settings" = '{"theme":"dark","notifications":true}'
```

> **Note** Only `jsonb` columns can be queried by their properties, since `json` has no operators for it, and a `json` column raises an `ArgumentError`. Columns holding a list of documents are compared as a whole, and a property that a strict class does not declare raises an `ArgumentError`.

### Sorting and grouping

The same `Hash` reaches a property wherever Rails takes a column, so `order`, `group`, `pluck` and `having` work over the document as well, and the property is cast the same way.
```ruby
Profile.order(settings: { theme: :asc })
# ORDER BY ("profiles"."settings" #>> ARRAY['theme']) ASC

Profile.order(settings: { notifications: :desc })
# ORDER BY ("profiles"."settings" #>> ARRAY['notifications'])::boolean DESC

Profile.group(settings: :theme).count
# GROUP BY ("profiles"."settings" #>> ARRAY['theme'])  => {"dark" => 1, "light" => 1}

Profile.group(:settings).having(settings: { theme: 'dark' })
# HAVING (("profiles"."settings" #>> ARRAY['theme']) = 'dark')

Profile.pluck(settings: :theme)                 # ["dark", "light"]
Profile.order(:settings)                        # The whole document, ordered as jsonb
```

The gem's own [`distinct_on`]({{ site.baseurl }}/querying/distinct-on/), [`buckets`]({{ site.baseurl }}/querying/buckets/), [`join_series`]({{ site.baseurl }}/querying/join-series/) and the `Hash` form of calculations resolve a property the same way.
```ruby
Profile.distinct_on(settings: :theme)
Profile.maximum(settings: :score)
```

> **Note** Rails resolves one level when sorting and grouping, so a property of a nested document is only reachable in `where`, or through the node below. Columns holding a list of documents are not resolved this way, and `having` follows PostgreSQL's rule that the property has to be grouped or aggregated.

### The Arel node

`arel_property_of` builds the node for any path into a document column, which is the way to use a property wherever an Arel node is accepted, at any depth. It goes through the struct class when there is one, so declared properties are cast and a strict class still refuses what it does not declare, and it works on any `jsonb` column, backed by a class or not.
```ruby
Profile.arel_property_of(:settings, :notifications)
# ("profiles"."settings" #>> ARRAY['notifications'])::boolean

Profile.arel_property_of(:settings, :address, :city)
# ("profiles"."settings" #>> ARRAY['address', 'city'])

Video.arel_property_of(:metadata, :file, :duration)
# ("videos"."metadata" #>> ARRAY['file', 'duration'])

Profile.order(Profile.arel_property_of(:settings, :address, :city).desc)
Video.where(Video.arel_property_of(:metadata, :file, :duration).gt('10'))
```

## Delegation

The `delegate` option adds the reader and the writer of the given properties to the record itself.
```ruby
class Profile < ActiveRecord::Base
  struct_for :settings, Settings, delegate: %i[theme]
end

profile.theme = 'dark'
profile.theme                    # 'dark'
profile.settings.theme           # 'dark'
```

## Undeclared properties

Documents may hold properties that the class does not declare, usually because they were stored before the class had them. Those are always preserved, they are never cast, and they can be read with `[]`.
```ruby
# settings => {"theme": "dark", "legacy": 123}
profile.settings[:legacy]        # 123
profile.settings[:theme]         # 'dark', declared properties go through their accessors

profile.settings.theme = 'light'
profile.save!
# settings => {"theme": "light", "legacy": 123}
```

Writing a property that the class does not declare is only allowed when the class is not strict, which is defined by [`struct.default_strict`]({{ site.baseurl }}/getting-started/configuring/#struct.default_strict). Strict classes raise `ActiveModel::UnknownAttributeError`, and it can be changed per class, or per column with the `strict` option.
```ruby
profile.settings[:other] = 'x'   # ActiveModel::UnknownAttributeError

class Profile::Settings < Torque::PostgreSQL::Struct
  self.strict = false
end

struct_for :settings, Settings, strict: false

profile.settings[:other] = 'x'   # Stored as it is
profile.settings[:other]         # 'x'
```

> **Note** Being strict never affects what is already stored. Undeclared properties of stored documents are always readable and always written back.

## Validations

Validations declared on the struct class run whenever the record is validated, as long as there is a document to store. A single `:invalid` error is added to the column, and every entry is validated for the array flavors.
```ruby
profile.settings.theme = 'bogus'
profile.valid?                             # false
profile.errors.added?(:settings, :invalid) # true
```

## Encryption

Individual properties can be encrypted, so that their values are stored encrypted inside the document, while the rest of it remains readable. This is Active Record's own `encrypts`, so all of its options are available.
```ruby
class Profile::Credentials < Torque::PostgreSQL::Struct
  attribute :label, :string
  attribute :token, :string

  encrypts :token
  encrypts :label, deterministic: true   # Same content produces the same ciphertext
end

# settings => {"label": "a", "token": "{\"p\":\"5nQ==\",\"h\":{...}}"}
profile.settings.token                   # 'secret'
profile.settings.ciphertext_for(:token)  # The stored ciphertext
Profile::Credentials.encrypted_attributes # #<Set: {:token, :label}>
```

> **Note** Encrypting the column itself is not supported, and it raises an `ArgumentError`. Encryption is supported on individual properties instead. Encrypting a property that the class does not declare raises an `ArgumentError` as well.

## Other Active Record features

Struct classes are ActiveModel classes with the parts of Active Record that make sense off a table, so several of the macros you already use are available inside them.

`enum` works as it does on a model, except that everything which needs a relation or a persisted record is left out. Only the predicates are generated, so there are no `active!` bang methods and no scopes.
```ruby
class Profile::Settings < Torque::PostgreSQL::Struct
  attribute :status, :string
  enum :status, { active: 'a', off: 'o' }
end

settings.status                  # 'active'
settings.active?                 # true
Profile::Settings.statuses       # {"active" => "a", "off" => "o"}
```

`normalizes` is applied on assignment, exactly like on a model.
```ruby
normalizes :email, with: -> email { email.strip.downcase }
```

`store_accessor` expands the keys of a property that holds a document of its own.
```ruby
class Profile::Settings < Torque::PostgreSQL::Struct
  attribute :extras, ActiveRecord::Type::Json.new
  store_accessor :extras, :locale
end

settings.locale = 'pt-BR'
settings.extras                  # {"locale" => "pt-BR"}
settings.locale_changed?         # true
```

Validations, callbacks (`before_validation`), and `as_json` / `to_json` are available as well, and serialization only ever exposes the properties.
```ruby
settings.as_json                 # {"theme" => "dark", "notifications" => true}
```

> **Note** Anything that depends on a record being saved is out of reach, which means enum scopes, `value!` methods, and the `saved_change_to_*` family of `store_accessor` are not defined.

## Changes

Everything is tracked as any other attribute of the record, including changes made in place, and reading a value never marks a record as changed.
```ruby
profile.settings.theme = 'dark'
profile.changed?                 # true
profile.settings.theme = 'light'
profile.changed?                 # false, it went back to what is stored
```

The instance exposes its own changes as well.
```ruby
profile.settings.theme_changed?  # true
profile.settings.changes         # {'theme' => ['light', 'dark']}
```

> **Note** Changes made in place are detected once the column has been read, which is how Rails handles any other mutable attribute.
