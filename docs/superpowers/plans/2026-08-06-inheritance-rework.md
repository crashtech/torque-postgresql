# Table Inheritance Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make physically inherited (PostgreSQL `INHERITS`) rows always instantiate as their correct model class, with read-only partial records and a per-table `expand_records` strategy that composes through `includes`.

**Architecture:** Casting becomes unconditional — every instantiating query on a hierarchy parent carries `tableoid::regclass AS _record_class`, and `instantiate_instance_of` resolves the real class from it. Records holding only ancestor-table columns are marked partial and read-only; `reload` upgrades them. `expand_records` replaces `cast_records`, defaulting to one narrow query per child table (merged into already-built records) with the old JOIN strategy available via `eager_load: true`.

**Tech Stack:** Ruby, ActiveRecord 8.0.2, PostgreSQL, RSpec, Arel.

**Design spec:** `docs/superpowers/specs/2026-08-06-inheritance-rework-design.md`

## Global Constraints

- Target ActiveRecord version is 8.0.2 (vendored at `.bundle/ruby/3.3.0/gems/activerecord-8.0.2/`). Cite it when overriding AR internals.
- All files start with `# frozen_string_literal: true`.
- **Zero inline comments explaining what code does.** Only short comments for non-obvious business requirements. Match the existing comment style in `lib/torque/postgresql/inheritance.rb` — a brief descriptive comment above each public method, nothing inside method bodies.
- Naming convention for class-level inheritance metadata is the `inheritance_` prefix (matching `inheritance_dependents`, `inheritance_merged_attributes`, `inheritance_mergeable_attributes`).
- Run the full suite with `bundle exec rspec`. Run the inheritance file with `bundle exec rspec spec/tests/table_inheritance_spec.rb`.
- **Baseline before any changes: 616 examples, 0 failures, 3 pending.** The inheritance file alone: 44 examples, 0 failures, 1 pending. The suite must be green at the end of every task.
- This is a breaking change for a major version bump. Do not add deprecation shims.

## Baseline facts about the spec fixtures

Needed by several tasks; do not re-derive them.

- Hierarchy (`spec/schema.rb:158-174`): `activities` ← `activity_books`, `activity_posts` (also inherits `images`), and `activity_post_samples` ← `activity_posts`. Also `questions` ← `question_selects` (UUID primary key).
- `activity_post_samples` is declared with **no body**, so `ActivityPost::Sample` adds no columns beyond `activity_posts`. Relative to `Activity` it still has extras (`post_id`, `url`, `activated`), so it *is* expandable from `Activity` but *not* from `ActivityPost`. This is the fixture for the "child that adds no columns is never partial" requirement.
- `Activity.inheritance_dependents` is `%w(activity_books activity_posts activity_post_samples)` in that order (`spec/tests/table_inheritance_spec.rb:225`).
- `spec/models/author.rb` currently declares `has_many :activities, -> { cast_records }`. Task 7 changes it.
- `Author`/`AuthorJournalist` are plain STI on `authors` and must keep working untouched.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `lib/torque/postgresql/inheritance.rb` | class resolution, partial instantiation, cached class-level metadata | 1, 4 |
| `lib/torque/postgresql/inheritance/record.rb` (new) | `partial_record?`, partial-state transitions, `reload` override | 2 |
| `lib/torque/postgresql/inheritance/expander.rb` (new) | group partials, narrow queries, merge attribute sets | 6 |
| `lib/torque/postgresql/relation/inheritance.rb` | discriminator injection, `itself_only`, `expand_records`, `exec_queries` hook | 3, 5, 6 |
| `lib/torque/postgresql/relation.rb` | register relation value methods | 5 |
| `lib/torque/postgresql/relation/merger.rb` | carry expand values across `merge` | 7 |
| `spec/mocks/cache_query.rb` | query-counting helper for the expansion specs | 6 |
| `lib/torque/postgresql/base.rb` | remove the lazy `_record_class` pluck | 4 |
| `lib/torque/postgresql/config.rb` | remove dead `auto_cast_column_name` | 4 |
| `spec/tests/table_inheritance_spec.rb` | all behavior specs | 1-7 |
| `spec/models/author.rb` | drop the `cast_records` association scope | 7 |

---

### Task 1: Class-level metadata cache — reset and thread-safe initialization

**Files:**
- Modify: `lib/torque/postgresql/inheritance.rb:27-83`
- Test: `spec/tests/table_inheritance_spec.rb`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `Model.inheritance_expandable_dependents` → frozen `Hash{String => Class}` mapping child table name to model class, containing only dependents that add columns relative to the receiver. Also a private `inheritance_cache(ivar_name) { ... }` helper returning the memoized value.

- [ ] **Step 1: Write the failing tests**

Add to `spec/tests/table_inheritance_spec.rb` inside the existing `context 'on inheritance' do` block (after the `casted_dependents` example around line 243):

```ruby
    it 'only considers dependents that add columns as expandable' do
      expect(base.inheritance_expandable_dependents.keys).to \
        eql(%w(activity_books activity_posts activity_post_samples))
      expect(child.inheritance_expandable_dependents).to be_empty
      expect(child2.inheritance_expandable_dependents).to be_empty
    end

    it 'recomputes inheritance metadata after resetting column information' do
      base.casted_dependents
      base.inheritance_expandable_dependents
      base.reset_column_information

      expect(base.instance_variable_get(:@casted_dependents)).to be_nil
      expect(base.instance_variable_get(:@inheritance_expandable_dependents)).to be_nil
      expect(base.casted_dependents.values.map(&:name)).to \
        eql(%w(ActivityBook ActivityPost ActivityPost::Sample))
    end
```

Note `child` is `ActivityPost` and `child2` is `ActivityBook` in that context (lines 194-195). `ActivityPost`'s only dependent adds no columns, and `ActivityBook` has no dependents at all — both expect empty.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb -e 'expandable' -e 'recomputes inheritance metadata'`
Expected: FAIL — `NoMethodError: undefined method 'inheritance_expandable_dependents'`.

- [ ] **Step 3: Add the cache helper and the new metadata method**

In `lib/torque/postgresql/inheritance.rb`, replace the four existing memoized methods so they route through one helper, and add the new one. Replace lines 27-83 (`inheritance_merged_attributes` through `casted_dependents`) with:

```ruby
        # Get a full list of all attributes from a model and all its dependents
        def inheritance_merged_attributes
          inheritance_cache(:@inheritance_merged_attributes) do
            children = casted_dependents.values.flat_map(&:attribute_names)
            attribute_names.to_set.merge(children).to_a.freeze
          end
        end

        # Get the list of attributes that can be merged while querying because
        # they all have the same type
        def inheritance_mergeable_attributes
          inheritance_cache(:@inheritance_mergeable_attributes) do
            base = inheritance_merged_attributes - attribute_names
            types = base.zip(base.size.times.map { [] }).to_h

            casted_dependents.values.each do |klass|
              klass.attribute_types.each do |column, type|
                types[column]&.push(type)
              end
            end

            result = types.filter_map do |attribute, types|
              attribute if types.each_with_object(types.shift).all?(&:==)
            end

            (attribute_names + result).freeze
          end
        end

        # Check if the model's table depends on any inheritance
        def physically_inherited?
          inheritance_cache(:@physically_inherited) do
            connection.schema_cache.dependencies(
              defined?(@table_name) ? @table_name : decorated_table_name,
            ).present?
          end
        rescue ActiveRecord::ConnectionNotEstablished
          false
        end

        # Get the list of all tables directly or indirectly dependent of the
        # current one
        def inheritance_dependents
          connection.schema_cache.associations(table_name) || []
        end

        # Check whether the model's table has directly or indirectly dependents
        def physically_inheritances?
          inheritance_dependents.present?
        end

        # Get the list of all ActiveRecord classes directly or indirectly
        # associated by inheritance
        def casted_dependents
          inheritance_cache(:@casted_dependents) do
            inheritance_dependents.map do |table_name|
              [table_name, connection.schema_cache.lookup_model(table_name)]
            end.to_h.freeze
          end
        end

        # Get the dependents that actually add columns, which are the only ones
        # that produce incomplete records when loaded from this table
        def inheritance_expandable_dependents
          inheritance_cache(:@inheritance_expandable_dependents) do
            casted_dependents.select do |_table_name, klass|
              (klass.attribute_names - attribute_names).any?
            end.freeze
          end
        end
```

- [ ] **Step 4: Add the private helper and the reset hook**

In the same file, add a `protected` section before the existing `private` (line 139) containing the reset, and add the helper into the `private` section:

```ruby
        protected

          # Inheritance metadata is derived from the schema, so it must be
          # dropped whenever ActiveRecord drops its own schema-derived caches
          def reload_schema_from_cache(recursive = true)
            @physically_inherited = nil
            @casted_dependents = nil
            @inheritance_merged_attributes = nil
            @inheritance_mergeable_attributes = nil
            @inheritance_expandable_dependents = nil
            super
          end

        private

          # Memoize with the same double-checked locking that ActiveRecord uses
          # for loading the schema
          def inheritance_cache(name)
            current = instance_variable_get(name)
            return current unless current.nil?

            # why: @load_schema_monitor is still nil while AR's inherited reaches base_class
            (@load_schema_monitor ||= Monitor.new).synchronize do
              current = instance_variable_get(name)
              return current unless current.nil?

              instance_variable_set(name, yield)
            end
          end
```

The `||=` fallback is required, not defensive. `ModelSchema::ClassMethods#inherited` (`model_schema.rb:574-581`) calls `super` on line 575 *before* `child_class.initialize_load_schema_monitor` on line 576, and that `super` traverses `Delegation::DelegateCache#inherited` → `base_class?` → torque's `base_class` (`inheritance.rb:124-126`) → `physically_inherited?`. Without the fallback, every model class definition raises `NoMethodError: undefined method 'synchronize' for nil`. AR overwrites the ivar on line 576 immediately after, and line 577's `reload_schema_from_cache(false)` clears anything memoized under the temporary monitor.

`reload_schema_from_cache` must stay **protected**, not private: AR calls it with an explicit receiver at `model_schema.rb:577` (`child_class.reload_schema_from_cache(false)`), which a private method would reject. `@load_schema_monitor` is created per class at `model_schema.rb:549-550` and is a reentrant `Monitor`, so `inheritance_expandable_dependents` synchronizing while calling `casted_dependents` (which also synchronizes) cannot deadlock.

- [ ] **Step 5: Run the new tests**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb -e 'expandable' -e 'recomputes inheritance metadata'`
Expected: PASS, 2 examples.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: 618 examples, 0 failures, 3 pending. (Baseline 616 plus the 2 new.)

- [ ] **Step 7: Commit**

```bash
git add lib/torque/postgresql/inheritance.rb spec/tests/table_inheritance_spec.rb
git commit -m "Reset and synchronize inheritance metadata caches

Route the memoized class-level inheritance metadata through one helper
that uses ActiveRecord's own load_schema_monitor, and drop all of it from
reload_schema_from_cache so it is recomputed whenever the schema caches
are cleared. Adds inheritance_expandable_dependents, which lists only the
dependents that add columns."
```

---

### Task 2: Partial record state

**Files:**
- Create: `lib/torque/postgresql/inheritance/record.rb`
- Modify: `lib/torque/postgresql/inheritance.rb` (require and include the new module)
- Test: `spec/tests/table_inheritance_spec.rb`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: instance methods on every model — `partial_record?` → `Boolean`; private `mark_as_partial_record!` and `mark_as_full_record!`, both returning nothing meaningful and both invoked via `send` from other units. `reload` clears partial state.

- [ ] **Step 1: Write the failing tests**

Add a new top-level context to `spec/tests/table_inheritance_spec.rb`, before `context 'on relation' do` (line 266):

```ruby
  context 'on partial records' do
    let(:record) { Activity.create!(title: 'Activity test') }

    it 'is neither partial nor read-only by default' do
      expect(record.partial_record?).to be_falsey
      expect(record.readonly?).to be_falsey
    end

    it 'becomes read-only when marked as partial' do
      record.send(:mark_as_partial_record!)

      expect(record.partial_record?).to be_truthy
      expect(record.readonly?).to be_truthy
      expect { record.update!(title: 'Changed') }.to \
        raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it 'clears both flags when marked as full' do
      record.send(:mark_as_partial_record!)
      record.send(:mark_as_full_record!)

      expect(record.partial_record?).to be_falsey
      expect(record.readonly?).to be_falsey
    end

    it 'clears the partial state on reload' do
      record.send(:mark_as_partial_record!)
      record.reload

      expect(record.partial_record?).to be_falsey
      expect(record.readonly?).to be_falsey
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb -e 'on partial records'`
Expected: FAIL — `NoMethodError: undefined method 'partial_record?'`.

- [ ] **Step 3: Create the module**

Create `lib/torque/postgresql/inheritance/record.rb`:

```ruby
# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Inheritance
      module Record

        # Whether the record was loaded from one of its ancestor tables and
        # therefore is missing the columns that only exist on its own table
        def partial_record?
          @partial_record == true
        end

        # Reload always queries the record's own table, which produces a
        # complete and writable record
        def reload(*)
          super.tap { mark_as_full_record! }
        end

        private

          def mark_as_partial_record!
            @partial_record = true
            readonly!
          end

          def mark_as_full_record!
            @partial_record = false
            @readonly = false
          end

      end
    end
  end
end
```

- [ ] **Step 4: Require and include it**

At the top of `lib/torque/postgresql/inheritance.rb`, after the `# frozen_string_literal: true` line, add:

```ruby
require_relative 'inheritance/record'
```

Then at the bottom of the same file, change line 195 from:

```ruby
    ActiveRecord::Base.include Inheritance
```

to:

```ruby
    ActiveRecord::Base.include Inheritance
    ActiveRecord::Base.include Inheritance::Record
```

`Record` must be included **after** `Inheritance` so its `reload` sits closer to the class than `ActiveRecord::AttributeMethods::Dirty#reload` (`attribute_methods/dirty.rb:63-68`) and `ActiveRecord::Persistence#reload` (`persistence.rb:742-757`). `super` then chains through both, and `mark_as_full_record!` runs last — which matters because `Persistence#reload` replaces `@attributes` wholesale and never touches `@readonly`.

- [ ] **Step 5: Run the tests**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb -e 'on partial records'`
Expected: PASS, 4 examples.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: 622 examples, 0 failures, 3 pending.

- [ ] **Step 7: Commit**

```bash
git add lib/torque/postgresql/inheritance/record.rb lib/torque/postgresql/inheritance.rb spec/tests/table_inheritance_spec.rb
git commit -m "Add partial record state

Records loaded from an ancestor table are missing their own table's
columns. Mark them as partial and read-only, and clear both flags on
reload, which always queries the record's own table."
```

---

### Task 3: Discriminator injection

Makes every instantiating query on a hierarchy parent carry `_record_class`, from a single source.

**This task is not independently valid, and its commit is not a bisect point.** Adding the column activates the *pre-existing* casting path in `instantiate_instance_of`: the old guard `return if record[_auto_cast_attribute.to_s] == false` never fires when `_auto_cast` is absent, because `nil == false` is `false`. So from this commit until Task 4 lands, a plain `Activity.where(...)` returns an `ActivityBook` that is **editable and missing its own columns** — `partial_record?` is `false`, `readonly?` is `false`, and reading `url` raises `MissingAttributeError`. The full suite stays green because no existing example reads a child-only column off a plain query. Task 4 resolves it by rewriting instantiation and marking such records partial. Verified empirically; accepted as transient by the project owner.

**Files:**
- Modify: `lib/torque/postgresql/relation/inheritance.rb:51-71`
- Test: `spec/tests/table_inheritance_spec.rb:278-281`

**Interfaces:**
- Consumes: `Model.physically_inheritances?` (pre-existing).
- Produces: a private `build_record_class_marker` returning the aliased Arel node, and a private `inheritance_discriminated?` → `Boolean` deciding whether to inject. `cast_records!` no longer adds the marker itself.

- [ ] **Step 1: Write the failing test**

In `spec/tests/table_inheritance_spec.rb`, replace the existing example at lines 278-281:

```ruby
      it 'does not mess with original queries' do
        expect(base.all.to_sql).to \
          eql('SELECT "activities".* FROM "activities"')
      end
```

with:

```ruby
      it 'adds the record class to queries on a table with dependents' do
        result = 'SELECT "activities".*'
        result << ', "activities"."tableoid"::regclass AS _record_class'
        result << ' FROM "activities"'
        expect(base.all.to_sql).to eql(result)
      end

      it 'does not add the record class to a table without dependents' do
        expect(other.all.to_sql).to \
          eql("SELECT \"authors\".* FROM \"authors\" WHERE \"authors\".\"type\" = 'AuthorJournalist'")
      end
```

`other` is `AuthorJournalist` (line 269), which is plain STI with no physical dependents.

Do **not** add an example asserting `itself_only` omits the discriminator: the existing example at lines 283-286 already asserts `base.itself_only.to_sql` equals `'SELECT "activities".* FROM ONLY "activities"'`, which proves it by exact match. Adding a second would be a verbatim duplicate.

- [ ] **Step 2: Run the tests to verify the first fails**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb -e 'adds the record class to queries'`
Expected: FAIL — actual SQL is `SELECT "activities".* FROM "activities"` without the `_record_class` column.

- [ ] **Step 3: Inject the discriminator in build_arel**

In `lib/torque/postgresql/relation/inheritance.rb`, replace the `build_arel` and `cast_records!` bodies. Change `cast_records!` (lines 56-61) to drop the marker line:

```ruby
        # Like #cast_records, but modifies relation in place
        def cast_records!(*types, **options)
          where!(regclass.pg_cast(:varchar).in(types.map(&:table_name))) if options[:filter]
          self.cast_records_values = (types.present? ? types : model.casted_dependents.values)
          self
        end
```

Then replace `build_arel` (lines 66-71) with:

```ruby
          # Hook arel build to add any necessary table
          def build_arel(*)
            arel = super
            arel.only if self.itself_only_value === true
            self.select_extra_values += [build_record_class_marker] if inheritance_discriminated?
            build_inheritances(arel)
            arel
          end

          # Records can only be instantiated as their real class when the query
          # says which table each row came from. Reading from ONLY the table
          # makes that unnecessary, since every row belongs to it
          def inheritance_discriminated?
            model.physically_inheritances? && !(self.itself_only_value === true)
          end

          def build_record_class_marker
            regclass.as(_record_class_attribute.to_s)
          end
```

Order matters: the marker is appended to `select_extra_values` **before** `build_inheritances`, so `_record_class` precedes the join columns. That keeps the existing `cast_records` SQL expectations at lines 312-316 valid. The outer `Relation#build_arel` (`relation.rb:96-100`) projects `select_extra_values` after this inner hook returns, which is why appending here works at all.

- [ ] **Step 4: Run the inheritance file**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb`
Expected: PASS, 51 examples, 0 failures, 1 pending (44 baseline + 2 from Task 1 + 4 from Task 2, then net +1 here since Step 1 replaces one example with two). The `cast_records` SQL specs (lines 311-341) and the `count`/`sum` specs (lines 343-361) must pass **unchanged** — the latter prove the extra column stays out of calculations.

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: 623 examples, 0 failures, 3 pending.

If anything outside the inheritance file fails here, it is a query on `activities`, `activity_posts` or `questions` asserting exact SQL. Update those assertions to include the marker; do not weaken the injection.

- [ ] **Step 6: Commit**

```bash
git add lib/torque/postgresql/relation/inheritance.rb spec/tests/table_inheritance_spec.rb
git commit -m "Always select the record class for inherited tables

Inject tableoid::regclass as a single source in build_arel rather than
only when casting was requested, so every instantiating query knows which
table each row came from. Skipped for itself_only, where every row
belongs to the queried table."
```

---

### Task 4: Always instantiate the correct class

The semantic core. After this, casting is unconditional, `_auto_cast` is gone, and `_record_class` is no longer a readable attribute.

**Files:**
- Modify: `lib/torque/postgresql/inheritance.rb:10-24,139-191`
- Modify: `lib/torque/postgresql/relation/inheritance.rb:90,114-117`
- Modify: `lib/torque/postgresql/relation.rb:112-115`
- Modify: `lib/torque/postgresql/base.rb:37-47`
- Modify: `lib/torque/postgresql/config.rb:175-178`
- Test: `spec/tests/table_inheritance_spec.rb`

**Interfaces:**
- Consumes: `Model.inheritance_expandable_dependents` (Task 1), `mark_as_partial_record!` (Task 2), the `_record_class` column (Task 3).
- Produces: `instantiate_instance_of(klass, attributes, types = {}, &block)` returning a correctly-classed record, marked partial when applicable. A private `sanitize_attributes(real_class, attributes, types)` returning `[Hash, Hash]` of name-keyed values and types. Removes `cast_record`, `_auto_cast_attribute`, and `torque_discriminate_class_for_record`.

- [ ] **Step 1: Write the failing tests**

Add a new top-level context to `spec/tests/table_inheritance_spec.rb`, immediately after the `context 'on partial records' do` block from Task 2:

```ruby
  context 'on automatic casting' do
    before :each do
      Activity.create!(title: 'Plain activity')
      ActivityBook.create!(title: 'A book', url: 'bookurl1')
      ActivityPost.create!(title: 'A post', url: 'posturl1')
      ActivityPost::Sample.create!(title: 'A sample')
    end

    it 'returns the correct class without any opt-in' do
      expect(Activity.order(:id).load.map(&:class)).to \
        eql([Activity, ActivityBook, ActivityPost, ActivityPost::Sample])
    end

    it 'marks casted records as partial and read-only' do
      records = Activity.order(:id).load.to_a

      expect(records[0].partial_record?).to be_falsey
      expect(records[0].readonly?).to be_falsey
      expect(records[1].partial_record?).to be_truthy
      expect(records[1].readonly?).to be_truthy
    end

    it 'raises when reading a column that was not loaded' do
      book = Activity.order(:id).load.to_a[1]
      expect { book.url }.to raise_error(ActiveModel::MissingAttributeError)
    end

    it 'raises when persisting a partial record' do
      book = Activity.order(:id).load.to_a[1]
      expect { book.update!(title: 'Changed') }.to \
        raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it 'does not mark a dependent that adds no columns as partial' do
      sample = ActivityPost.order(:id).load.to_a.last

      expect(sample).to be_instance_of(ActivityPost::Sample)
      expect(sample.partial_record?).to be_falsey
      expect(sample.readonly?).to be_falsey
      expect(sample.update!(title: 'Changed')).to be_truthy
    end

    it 'loads the full record on reload' do
      book = Activity.order(:id).load.to_a[1]
      book.reload

      expect(book.url).to eql('bookurl1')
      expect(book.partial_record?).to be_falsey
      expect(book.readonly?).to be_falsey
      expect(book.changed?).to be_falsey
    end

    it 'does not expose the internal record class attribute' do
      book = Activity.order(:id).load.to_a[1]

      expect(book).to be_instance_of(ActivityBook)
      expect(book).not_to respond_to(:_record_class)
      expect(book).not_to respond_to(:_auto_cast)
    end

    it 'does not affect single table inheritance' do
      AuthorJournalist.create!(name: 'An author name')
      expect(AuthorJournalist.first).to be_instance_of(AuthorJournalist)
    end

    context 'when a record class cannot be resolved' do
      after { Activity.reset_column_information }

      it 'raises pointing at the irregular models setting' do
        Activity.instance_variable_set(:@casted_dependents, {})

        expect { Activity.order(:id).load.to_a }.to \
          raise_error(Torque::PostgreSQL::InheritanceError, /activity_books/)
      end
    end

    context 'using uuid' do
      it 'returns the correct class' do
        Question.create!(title: 'Simple question')
        QuestionSelect.create!(title: 'Select question')

        expect(Question.order(:created_at).load.map(&:class)).to \
          eql([Question, QuestionSelect])
      end
    end
  end
```

The resolution-failure example replaces the one being deleted with lines 401-449 (`rises an error when the casted model cannot be defined`, old lines 415-418), which was the only coverage of `raise_unable_to_cast`. The `after` hook is required because `@casted_dependents` is memoized across examples; `reset_column_information` now clears it thanks to Task 1.

The `ActivityPost.order(:id)` case is the "no extra columns" fixture: `ActivityPost::Sample` adds nothing beyond `activity_posts`, so it must be complete and writable.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb -e 'on automatic casting'`
Expected: FAIL — the first example reports `[Activity, Activity, Activity, Activity]` because casting has not been wired up.

- [ ] **Step 3: Rewrite instantiation**

In `lib/torque/postgresql/inheritance.rb`, delete the `cast_record` instance method (lines 10-21) entirely. Change the delegation on line 24 from:

```ruby
        delegate :_auto_cast_attribute, :_record_class_attribute, to: ActiveRecord::Relation
```

to:

```ruby
        delegate :_record_class_attribute, to: ActiveRecord::Relation
```

Then replace the whole private section (lines 141-191, `instantiate_instance_of` through `torque_discriminate_class_for_record`) with:

```ruby
          # Rows coming from a table with dependents carry the table they were
          # stored in, which is what decides the class to instantiate
          def instantiate_instance_of(klass, attributes, types = {}, &block)
            return super unless klass.physically_inheritances?

            record_class = attributes[_record_class_attribute.to_s]
            return super if record_class.blank? || record_class == klass.table_name

            real_class = klass.casted_dependents[record_class]
            klass.raise_unable_to_cast(record_class) if real_class.nil?

            values, types = sanitize_attributes(real_class, attributes, types)
            record = super(real_class, values, types, &block)
            record.send(:mark_as_partial_record!) if klass.inheritance_expandable_dependents.key?(record_class)
            record
          end

          # Keep only what belongs to the real class: drop the internal record
          # class column, unprefixed columns from sibling tables, and prefixed
          # columns belonging to another table, unwrapping our own prefix
          def sanitize_attributes(real_class, attributes, types)
            prefix = "#{real_class.table_name}__"
            names = real_class.attribute_names.to_set
            skip = _record_class_attribute.to_s

            new_values = {}
            new_types = {}

            attributes.to_hash.each do |column, value|
              next if column == skip

              name =
                if column.start_with?(prefix)
                  column.delete_prefix(prefix)
                elsif column.include?('__') || names.exclude?(column)
                  next
                else
                  column
                end

              new_values[name] = value
              new_types[name] = types[column] if types.key?(column)
            end

            [new_values, new_types]
          end
```

This replaces the old `@row`/`@column_indexes` surgery with one rule that serves both the plain path (row is base columns plus `_record_class`) and the `eager_load` path (row also carries `table__column` aliases). `IndexedRow#to_hash` exists at `result.rb:60`. Dropping `_record_class` from the values is what keeps it out of the `AttributeSet`, which is why `respond_to?(:_record_class)` becomes false — it is readable today only because it sits in the attribute hash with no generated reader, so `method_missing` resolves it.

- [ ] **Step 4: Remove the auto-cast marker**

In `lib/torque/postgresql/relation/inheritance.rb`, delete the `build_auto_caster_marker` method (lines 114-117) and the line that pushes it in `build_inheritances` (line 90):

```ruby
            columns.push(build_auto_caster_marker(arel, self.cast_records_values))
```

In `lib/torque/postgresql/relation.rb`, delete the `_auto_cast_attribute` method (lines 112-115).

In `lib/torque/postgresql/config.rb`, delete the now-dead `auto_cast_column_name` setting (lines 175-178, the comment block and the assignment).

- [ ] **Step 5: Remove the lazy record class pluck**

In `lib/torque/postgresql/base.rb`, replace the `inherited` hook (lines 31-48) with:

```ruby
        # Whenever the base model is inherited, add a list of auxiliary
        # statements
        def inherited(subclass)
          super

          subclass.class_attribute(:auxiliary_statements_list)
          subclass.auxiliary_statements_list = {}
        end
```

The `dynamic_attribute(_record_class)` block issued one `pluck` per record to discover its table. The column now rides along in the main query.

- [ ] **Step 6: Update the existing specs this changes**

In `spec/tests/table_inheritance_spec.rb`:

1. Delete the `_auto_cast` clause from the three `cast_records` SQL expectations. At line 316 delete:

```ruby
        result << ", \"activities\".\"tableoid\"::regclass::varchar IN ('activity_books', 'activity_posts', 'activity_post_samples') AS _auto_cast"
```

At line 327 and line 336 delete:

```ruby
        result << ", \"activities\".\"tableoid\"::regclass::varchar IN ('activity_books') AS _auto_cast"
```

2. Replace the `does not cast unnecessary records` example (lines 374-381) — every record is cast now, so the distinction is completeness rather than class:

```ruby
      it 'only fully loads the requested records' do
        ActivityPost.create(title: 'Activity post')
        records = base.cast_records(ActivityBook).order(:id).load.to_a

        expect(records[1]).to be_instance_of(ActivityBook)
        expect(records[1].partial_record?).to be_falsey
        expect(records[2]).to be_instance_of(ActivityPost)
        expect(records[2].partial_record?).to be_truthy
      end
```

3. Convert the `xit` at line 392 to `it`, and delete the now-redundant duplicate covered by Task 4's new context. Keep it as:

```ruby
      it 'does not make internal inheritance attributes accessible' do
        record = base.cast_records.order(:id).load.last

        expect(record).to be_instance_of(ActivityBook)
        expect(record).not_to respond_to(:_record_class)
        expect(record).not_to respond_to(:_auto_cast)
      end
```

Note the fixture ordering in that context (lines 299-303) creates one `Activity` then one `ActivityBook`, so `.last` is the book.

4. Delete the entire `context 'cast record' do` block (lines 401-449). `cast_record` no longer exists; the behavior it covered — correct class and full load — is now covered by the new `on automatic casting` context, including its UUID case.

- [ ] **Step 7: Run the inheritance file**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb`
Expected: PASS, 0 failures, 0 pending. The pending `xit` is now a real passing example, and the 6 deleted `cast record` examples are replaced by the 10 new ones.

- [ ] **Step 8: Run the full suite**

Run: `bundle exec rspec`
Expected: 0 failures, 2 pending (the two unrelated `xit`s in `enum_set_spec.rb:58` and `insert_all_spec.rb:80`).

Any failure elsewhere is code depending on `cast_record`, `_record_class` as an attribute, or `_auto_cast`. Search with `grep -rn '_auto_cast\|cast_record\b' lib spec` and fix the call sites.

- [ ] **Step 9: Commit**

```bash
git add lib spec
git commit -m "Always instantiate inherited records as their real class

Casting no longer requires opting in, so the _auto_cast marker and the
per-record tableoid pluck are both gone, along with cast_record. Records
missing their own table's columns are marked partial. Attribute
sanitizing now works on a plain hash instead of reaching into the
result row's internals."
```

---

### Task 4b: Make the discriminator survive an explicit select

**Added during execution.** Task 4's review found that an explicit `select` skips casting entirely, because Task 3 injected the marker through `select_extra_values`, which `relation.rb:98` projects only `if select_values.blank?`. So `Activity.select(:id, :title)` returns a plain `Activity` for a row stored in `activity_books`, writable and unmarked — verified empirically. The project owner ruled the marker must always work, with its own mechanism if it cannot ride `select_extra_values`.

**Files:**
- Modify: `lib/torque/postgresql/relation/inheritance.rb`
- Modify: `lib/torque/postgresql/relation.rb` (register the new relation value)
- Test: `spec/tests/table_inheritance_spec.rb`

**Interfaces:**
- Consumes: `inheritance_discriminated?` and `build_record_class_marker` (Task 3), the partial-marking conjunction in `instantiate_instance_of` (Task 4).
- Produces: relation value `skip_record_class_value` → `Boolean`, suppressing marker injection on queries that never instantiate records.

**The two seams that must be suppressed.** `pluck` and the calculations both set `select_values` on a spawned relation and then read raw rows without instantiating, so they are indistinguishable from a user's `select` by content alone. They must be marked explicitly:

- `ActiveRecord::Calculations#calculate` (`relation/calculations.rb:217`) is the single funnel for `count`, `sum`, `average`, `minimum`, `maximum` — confirmed at `:102, :117, :132, :147, :176`.
- `ActiveRecord::Calculations#pluck` (`relation/calculations.rb:291`) is the other, setting `relation.select_values = columns` at `:316`.

Injecting the marker into either would add a column to `SELECT COUNT(*)` or corrupt `pluck`'s result rows.

- [ ] **Step 1: Write the failing tests**

Add to `spec/tests/table_inheritance_spec.rb`, in the `on automatic casting` context added by Task 4:

```ruby
    it 'casts records loaded through an explicit select' do
      book = ActivityBook.create!(title: 'Selected book', url: 'selurl')
      record = Activity.select(:id, :title).where(id: book.id).first

      expect(record).to be_instance_of(ActivityBook)
      expect(record.partial_record?).to be_truthy
      expect(record.readonly?).to be_truthy
    end

    it 'does not add the record class to plucked columns' do
      ActivityBook.create!(title: 'Plucked', url: 'plurl')
      expect(Activity.pluck(:title)).to all(be_a(String))
      expect(Activity.pluck(:id, :title).first.size).to eql(2)
    end

    it 'does not add the record class to calculations' do
      ActivityBook.create!(title: 'Counted', url: 'cnturl')
      expect(Activity.count).to be_a(Integer)
      expect(Activity.sum(:id)).to be_a(Integer)
    end
```

- [ ] **Step 2: Run to verify the first fails**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb -e 'casts records loaded through an explicit select'`
Expected: FAIL — the record comes back as `Activity`, not `ActivityBook`, because the marker is absent from the select list.

The pluck and calculation examples should already pass; they are the regression guard for step 3.

- [ ] **Step 3: Add the suppression flag and project directly**

In `lib/torque/postgresql/relation/inheritance.rb`, declare the flag key on the module:

```ruby
        SKIP_RECORD_CLASS = :torque_skip_record_class
```

Extend the predicate and split the projection by whether `select_extra_values` will be projected for us:

```ruby
          def inheritance_discriminated?
            return false if Thread.current[SKIP_RECORD_CLASS]
            return false if self.itself_only_value === true

            model.physically_inheritances?
          end
```

and in `build_arel`, keep the `select_extra_values` route when it will actually be projected, and project directly otherwise:

```ruby
          def build_arel(*)
            arel = super
            arel.only if self.itself_only_value === true

            if inheritance_discriminated?
              if select_values.blank?
                self.select_extra_values += [build_record_class_marker]
              else
                arel.project(build_record_class_marker)
              end
            end

            build_inheritances(arel)
            arel
          end
```

Keeping the `select_extra_values` route for the blank case preserves the existing SQL ordering that the `cast_records` expectations depend on.

`build_inheritances` stays called unconditionally, exactly as it is today — it already self-guards with `return if self.cast_records_values.empty?`. This task runs **before** Task 5, so the names in this file are still `cast_records_values` / `cast_records!`. Do not rename anything; Task 5 owns that.

- [ ] **Step 4: Suppress on the non-instantiating paths**

In the same file, add public overrides that mark the relation before delegating:

```ruby
        # Calculations read raw values and never instantiate records, so the
        # record class marker must not reach their select list
        def calculate(operation, column_name)
          return super unless model.physically_inheritances?

          without_record_class_marker { super }
        end

        # Plucking reads raw columns positionally, so an extra column would
        # corrupt the result rows
        def pluck(*column_names)
          return super unless model.physically_inheritances?

          without_record_class_marker { super }
        end
```

with the suppression itself private, alongside `inheritance_discriminated?`:

```ruby
          # why: pluck and calculations spawn their own relations internally,
          # so the suppression cannot live on this one
          def without_record_class_marker
            previous = Thread.current[SKIP_RECORD_CLASS]
            Thread.current[SKIP_RECORD_CLASS] = true
            yield
          ensure
            Thread.current[SKIP_RECORD_CLASS] = previous
          end
```

and `SKIP_RECORD_CLASS = :torque_skip_record_class` declared on the module. `inheritance_discriminated?` checks `Thread.current[SKIP_RECORD_CLASS]` rather than a relation value.

**Do not use a relation value with spawn-and-re-invoke here.** That was the first attempt and it fails: `Relation::Buckets` is included at `railtie.rb:30`, *after* `include Inheritance` at `relation.rb:14`, so `Buckets#calculate` sits outside this one. It installs `group_values` (`buckets.rb:53`) then calls `super`; respawning re-enters the chain from the top and `Buckets#calculate` raises at `:48` on the values it just set. Every bucketed aggregate breaks — first for all models, then, once gated on `physically_inheritances?`, for inheriting ones. Suppressing for the dynamic extent of the call avoids the re-entry entirely.

Suppression must also survive the relations that `pluck` (`relation/calculations.rb:313-316`) and the calculations spawn internally. An instance variable is not sufficient: `Relation#spawn` is `already_in_scope? ? klass.all : clone`, and the `klass.all` branch — taken inside a `scoping` block — produces a fresh relation carrying none of the original's ivars.

- [ ] **Step 5: Register the relation value**

No registration is needed in `lib/torque/postgresql/relation.rb`. The suppression is a dynamic-extent flag, not a relation value, so `SINGLE_VALUE_METHODS` and `VALID_UNSCOPING_VALUES` are left untouched.

- [ ] **Step 6: Run the inheritance file**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb`
Expected: PASS, 0 failures, 0 pending. The pre-existing `count`/`sum` SQL examples must pass **unchanged** — they are the proof the suppression works.

- [ ] **Step 7: Run the full suite**

Run: `bundle exec rspec`
Expected: 0 failures, 2 pending.

Any failure outside the inheritance file is most likely a `pluck` or aggregate on `activities`, `activity_posts` or `questions`. Diagnose rather than assume: a corrupted `pluck` result means the suppression is not reaching that path, which is a real bug, not an assertion to update.

- [ ] **Step 8: Commit**

```bash
git add lib spec
git commit -m "Make the record class marker survive an explicit select

Riding select_extra_values meant an explicit select dropped the marker
and silently skipped casting. Project it directly when a select is
present, and suppress it for pluck and calculations, which read raw
rows and would be corrupted by an extra column."
```

---

### Task 5: Rename to expand_records

API surface only. The default per-table strategy records its intent but does nothing yet; Task 6 makes it load.

**Files:**
- Modify: `lib/torque/postgresql/relation/inheritance.rb:9-61`
- Modify: `lib/torque/postgresql/relation.rb:16-19,145-146`
- Modify: `lib/torque/postgresql/relation/merger.rb:54-63`
- Test: `spec/tests/table_inheritance_spec.rb`

**Interfaces:**
- Consumes: `Model.inheritance_expandable_dependents` (Task 1).
- Produces: `Relation#expand_records(*models, eager_load: false, filter: false)` and `#expand_records!`. Relation values `expand_records_values` → `Array<Class>` and `expand_records_eager_load_value` → `Boolean`. Removes `cast_records` and `cast_records_values`.

- [ ] **Step 1: Write the failing tests**

In `spec/tests/table_inheritance_spec.rb`, rename the `context 'cast records' do` block (line 298) to `context 'expand records' do`, and replace every `cast_records` call inside it with `expand_records(eager_load: true)` — preserving arguments. The three SQL examples become `base.expand_records(eager_load: true).all.to_sql`, `base.expand_records(child, eager_load: true).all.to_sql`, and `base.expand_records(child, filter: true, eager_load: true).all.to_sql`. The `count`, `sum`, `returns the correct model object`, `only fully loads the requested records`, `correctly identifies same name attributes` and internal-attributes examples all take `eager_load: true` too.

Then add these new examples inside that same context:

```ruby
      it 'defaults to every dependent that adds columns' do
        relation = base.expand_records
        expect(relation.expand_records_values).to \
          eql(base.inheritance_expandable_dependents.values)
      end

      it 'limits the expansion to the given models' do
        relation = base.expand_records(child)
        expect(relation.expand_records_values).to eql([child])
      end

      it 'does not add joins without eager loading' do
        result = 'SELECT "activities".*'
        result << ', "activities"."tableoid"::regclass AS _record_class'
        result << ' FROM "activities"'
        expect(base.expand_records.all.to_sql).to eql(result)
      end

      it 'cannot be combined with itself only' do
        expect { base.itself_only.expand_records }.to \
          raise_error(Torque::PostgreSQL::InheritanceError, /itself_only/)
        expect { base.expand_records.itself_only }.to \
          raise_error(Torque::PostgreSQL::InheritanceError, /itself_only/)
      end
```

In that context `child` is `ActivityBook` (line 268).

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb -e 'expand records'`
Expected: FAIL — `NoMethodError: undefined method 'expand_records'`.

- [ ] **Step 3: Replace the relation API**

In `lib/torque/postgresql/relation/inheritance.rb`, replace the value accessors and public methods (lines 9-61) with:

```ruby
        # :nodoc:
        def expand_records_values
          @values.fetch(:expand_records, FROZEN_EMPTY_ARRAY)
        end
        # :nodoc:
        def expand_records_values=(value)
          assert_modifiable!
          @values[:expand_records] = value
        end

        # :nodoc:
        def expand_records_eager_load_value
          @values.fetch(:expand_records_eager_load, nil)
        end
        # :nodoc:
        def expand_records_eager_load_value=(value)
          assert_modifiable!
          @values[:expand_records_eager_load] = value
        end

        # :nodoc:
        def itself_only_value
          @values.fetch(:itself_only, nil)
        end
        # :nodoc:
        def itself_only_value=(value)
          assert_modifiable!
          @values[:itself_only] = value
        end

        delegate :quote_table_name, :quote_column_name, to: :connection

        # Specify that the results should come only from the table that the
        # entries were created on. For example:
        #
        #   Activity.itself_only
        #   # Does not return entries for inherited tables
        def itself_only
          spawn.itself_only!
        end

        # Like #itself_only, but modifies relation in place.
        def itself_only!(*)
          raise_itself_only_conflict! if expand_records_values.present?

          self.itself_only_value = true
          self
        end

        # Load the columns that only exist on the inherited tables, so that
        # records come out complete and writable. Defaults to every dependent
        # that adds columns
        #
        #   Activity.expand_records
        #   # Runs one additional query per inherited table
        #
        #   Activity.expand_records(ActivityBook, eager_load: true)
        #   # Runs a single query using outer joins
        def expand_records(*types, **options)
          spawn.expand_records!(*types, **options)
        end

        # Like #expand_records, but modifies relation in place
        def expand_records!(*types, eager_load: false, filter: false)
          raise_itself_only_conflict! if itself_only_value === true

          where!(regclass.pg_cast(:varchar).in(types.map(&:table_name))) if filter
          self.expand_records_values = (types.presence || model.inheritance_expandable_dependents.values)
          self.expand_records_eager_load_value = eager_load
          self
        end
```

Add the raiser to the private section:

```ruby
          def raise_itself_only_conflict!
            raise InheritanceError.new(<<~MSG.squish)
              Reading from ONLY a table never returns records from its
              inherited tables, so itself_only and expand_records cannot be
              combined.
            MSG
          end
```

Then update the two remaining references in the same file: in `build_arel`, change `build_inheritances(arel)` to only run for eager loading, and in `build_inheritances` swap the value name:

```ruby
          # Hook arel build to add any necessary table
          def build_arel(*)
            arel = super
            arel.only if self.itself_only_value === true
            self.select_extra_values += [build_record_class_marker] if inheritance_discriminated?
            build_inheritances(arel) if self.expand_records_eager_load_value
            arel
          end
```

and inside `build_inheritances`, replace both `self.cast_records_values` reads with `self.expand_records_values`.

- [ ] **Step 4: Register the new relation values**

In `lib/torque/postgresql/relation.rb`, change lines 16-19 to:

```ruby
      SINGLE_VALUE_METHODS = %i[itself_only buckets expand_records_eager_load]
      MULTI_VALUE_METHODS = %i[
        select_extra distinct_on auxiliary_statements expand_records
      ]
```

and lines 145-146 to:

```ruby
    ActiveRecord::QueryMethods::VALID_UNSCOPING_VALUES.merge(%i[expand_records itself_only
      expand_records_eager_load distinct_on auxiliary_statements buckets])
```

- [ ] **Step 5: Update the merger**

In `lib/torque/postgresql/relation/merger.rb`, replace `merge_inheritance` (lines 54-63) with:

```ruby
          # Merge settings related to inheritance tables
          def merge_inheritance
            return unless relation.is_a?(Relation::Inheritance)

            relation.itself_only_value = true if other.itself_only_value.present?

            return if other.expand_records_values.blank?

            relation.expand_records_values += other.expand_records_values
            relation.expand_records_values.uniq!
            relation.expand_records_eager_load_value = other.expand_records_eager_load_value
          end
```

- [ ] **Step 6: Run the inheritance file**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb`
Expected: PASS, 0 failures. The `eager_load: true` SQL expectations must match the pre-rename output exactly, minus the `_auto_cast` column removed in Task 4.

- [ ] **Step 7: Run the full suite**

Run: `bundle exec rspec`
Expected: 0 failures, 2 pending.

`spec/models/author.rb` still calls `cast_records` in its association scope and will now raise `NoMethodError`. Change it to `-> { expand_records(eager_load: true) }` for now — Task 7 removes the scope entirely. Also `grep -rn 'cast_records' lib spec` and fix any remaining references.

- [ ] **Step 8: Commit**

```bash
git add lib spec
git commit -m "Rename cast_records to expand_records

The name now describes loading the missing columns rather than changing
a record's class, which happens unconditionally. The previous outer-join
strategy is available through eager_load: true. Reading from ONLY a table
conflicts with expanding, so the two now raise when combined."
```

---

### Task 6: The expansion pass

Makes the default `expand_records` strategy actually load — one narrow query per child table, merged into records already built.

**Files:**
- Create: `lib/torque/postgresql/inheritance/expander.rb`
- Modify: `lib/torque/postgresql/inheritance.rb` (require the new file)
- Modify: `lib/torque/postgresql/relation/inheritance.rb` (add the `exec_queries` hook)
- Test: `spec/tests/table_inheritance_spec.rb`

**Interfaces:**
- Consumes: `expand_records_values` and `expand_records_eager_load_value` (Task 5), `partial_record?` and `mark_as_full_record!` (Task 2).
- Produces: `Inheritance::Expander.new(model, records, targets)` with `#call` returning the records array, having amended every partial record whose class is in `targets`.

- [ ] **Step 1: Add a query-counting helper**

`db-query-matchers` is not a dependency of this project, so add a counter next to the existing helpers in `spec/mocks/cache_query.rb`, inside `module CacheQuery`:

```ruby
    def capture_executed_queries(&block)
      queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        queries << payload[:sql] unless payload[:name] == 'SCHEMA' || payload[:cached]
      end

      block.call
      queries
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
```

`Mocks::CacheQuery` is already `config.include`d at `spec/spec_helper.rb:42`, so no configuration change is needed.

- [ ] **Step 2: Write the failing tests**

Add to `spec/tests/table_inheritance_spec.rb`, inside the `context 'expand records' do` block:

```ruby
      it 'loads the missing columns with one query per table' do
        ActivityPost.create(title: 'Activity post', url: 'posturl1')
        records = nil

        queries = capture_executed_queries do
          records = base.expand_records.order(:id).load.to_a
        end

        expect(queries.size).to eql(3)
        expect(records[1]).to be_instance_of(ActivityBook)
        expect(records[1].url).to eql('bookurl1')
        expect(records[2]).to be_instance_of(ActivityPost)
        expect(records[2].url).to eql('posturl1')
      end

      it 'produces complete and writable records' do
        record = base.expand_records.order(:id).load.to_a[1]

        expect(record.partial_record?).to be_falsey
        expect(record.readonly?).to be_falsey
        expect(record.update!(title: 'Changed')).to be_truthy
      end

      it 'does not leave expanded records dirty' do
        record = base.expand_records.order(:id).load.to_a[1]

        expect(record.changed?).to be_falsey
        expect(record.changes).to be_empty
      end

      it 'only selects the primary key and the extra columns' do
        queries = capture_executed_queries do
          base.expand_records(child).order(:id).load.to_a
        end

        expansion = queries.find { |sql| sql.include?('activity_books') }
        expect(expansion).to match(/SELECT "activity_books"\."id"/)
        expect(expansion).to include('"description"')
        expect(expansion).to include('"url"')
        expect(expansion).not_to include('"title"')
      end

      it 'leaves records partial when the inherited row is gone' do
        book = base.order(:id).load.to_a[1]
        ActivityBook.where(id: book.id).delete_all

        record = base.expand_records.order(:id).load.to_a[1]
        expect(record.partial_record?).to be_truthy
      end
```

Three queries: `activities`, then `activity_books`, then `activity_posts`. No query for `activity_post_samples`, because the fixtures in this context (lines 299-303) create no sample row and the expander skips tables with no matching records.

- [ ] **Step 3: Run to verify failure**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb -e 'loads the missing columns'`
Expected: FAIL — `ActiveModel::MissingAttributeError` on `records[1].url`, because nothing expands yet.

- [ ] **Step 4: Create the expander**

Create `lib/torque/postgresql/inheritance/expander.rb`:

```ruby
# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Inheritance
      class Expander

        def initialize(model, records, targets)
          @model = model
          @records = records
          @targets = targets
        end

        # Load the columns that are missing from each partial record using one
        # query per inherited table
        def call
          pending.each do |klass, records|
            amend(klass, records, fetch(klass, records.map(&:id)))
          end

          @records
        end

        private

          attr_reader :model, :targets

          def pending
            @records.select do |record|
              record.partial_record? && targets.include?(record.class)
            end.group_by(&:class)
          end

          def extra_columns(klass)
            klass.attribute_names - model.attribute_names
          end

          def fetch(klass, ids)
            columns = [klass.primary_key, *extra_columns(klass)]
            table = klass.arel_table
            query = klass.unscoped.select(*columns.map { |name| table[name] })

            klass.lease_connection.select_all(
              query.where(klass.primary_key => ids).arel,
              "#{klass.name} Expand",
            ).to_a.index_by { |row| row[klass.primary_key] }
          end

          def amend(klass, records, rows)
            columns = extra_columns(klass)

            records.each do |record|
              row = rows[record.id]
              next if row.nil?

              record.instance_variable_get(:@attributes).reverse_merge!(
                build_attributes(klass, columns, row),
              )

              record.send(:mark_as_full_record!)
            end
          end

          def build_attributes(klass, columns, row)
            attributes = columns.to_h do |name|
              [name, ::ActiveModel::Attribute.from_database(name, row[name], klass.attribute_types[name])]
            end

            ::ActiveModel::AttributeSet.new(attributes)
          end

      end
    end
  end
end
```

Three details that carry the dirty-tracking guarantee:

- `Attribute.from_database` (`attribute.rb:8`) builds a `FromDatabase`, whose `changed?` is `changed_from_assignment? || changed_in_place?` — both false for an unread value with no `original_attribute`.
- `reverse_merge!` is `other.merge(self)` (`attribute_set.rb:102-104`), so already-loaded base columns win and only the missing extras are added.
- The merge mutates the `AttributeSet` **in place**, so the memoized `AttributeMutationTracker` still references the same object. No tracker reset is needed and `changed?` stays false.

The set is built explicitly rather than through `attributes_builder.build_from_database` because a `LazyAttributeSet` carries types for *all* of the child's columns and `reverse_merge!` materializes it (`attribute_set/builder.rb:59-67`), injecting `Attribute.uninitialized` entries for every column outside the narrow select.

- [ ] **Step 5: Require it and add the hook**

In `lib/torque/postgresql/inheritance.rb`, add below the existing `require_relative` from Task 2:

```ruby
require_relative 'inheritance/expander'
```

In `lib/torque/postgresql/relation/inheritance.rb`, add to the private section:

```ruby
          # Records only carry the columns of the queried table, so expanding
          # has to happen after they have been instantiated
          def exec_queries(&block)
            records = super
            return records if expand_records_values.empty? || expand_records_eager_load_value

            Inheritance::Expander.new(model, records, expand_records_values).call
          end
```

- [ ] **Step 6: Run the new tests**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb -e 'expand records'`
Expected: PASS.

If `select_all` complains about the query, confirm the primary key comes back as a string key matching `row[klass.primary_key]`. For the UUID `questions` hierarchy the primary key is a `uuid` column, so `record.id` is a `String` and comparison is direct; for `activities` it is a `bigint`, and `select_all` returns it already type-cast to `Integer` by the PG adapter. If the lookup misses, index on `row[klass.primary_key].to_s` and look up with `record.id.to_s`.

- [ ] **Step 7: Run the full suite**

Run: `bundle exec rspec`
Expected: 0 failures, 2 pending.

- [ ] **Step 8: Commit**

```bash
git add lib spec
git commit -m "Add the per-table expansion pass

expand_records now issues one narrow query per inherited table, selecting
only the primary key and that table's extra columns, and merges the
result into the records already built. Attributes are merged in place as
from-database values, so expanded records are complete, writable and not
dirty."
```

---

### Task 7: Propagate expansion through includes

**Files:**
- Modify: `lib/torque/postgresql/relation/merger.rb`
- Modify: `lib/torque/postgresql/relation/inheritance.rb`
- Modify: `lib/torque/postgresql/relation.rb`
- Modify: `spec/models/author.rb`
- Test: `spec/tests/table_inheritance_spec.rb`

**Interfaces:**
- Consumes: `expand_records_values`, `expand_records_eager_load_value` (Task 5), `Inheritance::Expander` (Task 6).
- Produces: relation value `expand_records_scoped_values` → `Hash{Class => Array<Class>}` mapping a base model to the targets requested for it, plus a `preload_associations` override applying them.

**Why not the preload scope:** `Relation#preload_associations` (`relation.rb:1321-1328`) builds the `Preloader` with `scope: StrictLoadingScope || nil` and never passes the root relation, so `Preloader::Association#build_scope` has no channel to read these values from. The only scope it merges is `preload_scope`, shared across every association in the call, so it cannot carry per-model targets either. The expansion therefore runs as a pass over the preloaded targets after `super`. Because the expander batches across all owners at once, it is still one query per table.

- [ ] **Step 1: Write the failing test**

Add a new top-level context to `spec/tests/table_inheritance_spec.rb`, after the `on relation` context:

```ruby
  context 'on associations' do
    let(:author) { Author.create!(name: 'An author name') }

    before :each do
      Activity.create!(title: 'Plain activity', author: author)
      ActivityBook.create!(title: 'A book', url: 'bookurl1', author: author)
      ActivityPost.create!(title: 'A post', url: 'posturl1', author: author)
    end

    it 'returns the correct classes through a preloaded association' do
      activities = Author.includes(:activities).first.activities.sort_by(&:id)

      expect(activities.map(&:class)).to \
        eql([Activity, ActivityBook, ActivityPost])
    end

    it 'leaves preloaded records partial without expanding' do
      activities = Author.includes(:activities).first.activities.sort_by(&:id)

      expect(activities[1].partial_record?).to be_truthy
      expect { activities[1].url }.to raise_error(ActiveModel::MissingAttributeError)
    end

    it 'expands preloaded records when merged' do
      relation = Author.includes(:activities).merge(Activity.expand_records)
      activities = relation.first.activities.sort_by(&:id)

      expect(activities[1]).to be_instance_of(ActivityBook)
      expect(activities[1].url).to eql('bookurl1')
      expect(activities[1].partial_record?).to be_falsey
      expect(activities[1].changed?).to be_falsey
      expect(activities[2].url).to eql('posturl1')
    end

    it 'uses one query per table when expanding through an association' do
      queries = capture_executed_queries do
        Author.includes(:activities).merge(Activity.expand_records).load.to_a
      end

      expect(queries.size).to eql(4)
    end
  end
```

Four queries: `authors`, `activities`, `activity_books`, `activity_posts`.

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb -e 'on associations'`
Expected: the first two examples pass — correct classes already arrive through the preload because casting is unconditional. The `expands preloaded records when merged` example FAILS with `ActiveModel::MissingAttributeError`, because merging onto the `Author` relation never reaches the `activities` preload scope.

- [ ] **Step 3: Store merged expand values keyed by model**

In `lib/torque/postgresql/relation/inheritance.rb`, add another value accessor next to the others:

```ruby
        # :nodoc:
        def expand_records_scoped_values
          @values.fetch(:expand_records_scoped, nil) || {}
        end
        # :nodoc:
        def expand_records_scoped_values=(value)
          assert_modifiable!
          @values[:expand_records_scoped] = value
        end
```

Register it in `lib/torque/postgresql/relation.rb` by adding `expand_records_scoped` to `SINGLE_VALUE_METHODS`:

```ruby
      SINGLE_VALUE_METHODS = %i[itself_only buckets expand_records_eager_load expand_records_scoped]
```

and to the unscoping list:

```ruby
    ActiveRecord::QueryMethods::VALID_UNSCOPING_VALUES.merge(%i[expand_records itself_only
      expand_records_eager_load expand_records_scoped distinct_on auxiliary_statements buckets])
```

In `lib/torque/postgresql/relation/merger.rb`, extend `merge_inheritance` so a mismatched model records the request instead of dropping it:

```ruby
          # Merge settings related to inheritance tables
          def merge_inheritance
            return unless relation.is_a?(Relation::Inheritance)

            relation.itself_only_value = true if other.itself_only_value.present?

            return if other.expand_records_values.blank?

            if relation.model == other.model
              relation.expand_records_values += other.expand_records_values
              relation.expand_records_values.uniq!
              relation.expand_records_eager_load_value = other.expand_records_eager_load_value
            else
              relation.expand_records_scoped_values = relation.expand_records_scoped_values
                .merge(other.model => other.expand_records_values)
            end
          end
```

- [ ] **Step 4: Expand the preloaded targets**

In `lib/torque/postgresql/relation/inheritance.rb`, add to the private section:

```ruby
          # The preloader never receives the relation carrying the request, so
          # expanding has to happen once the association targets are loaded
          def preload_associations(records)
            super
            return if expand_records_scoped_values.blank?

            expand_records_scoped_values.each do |base_model, targets|
              preloaded_association_names.each do |name|
                reflection = model.reflect_on_association(name)
                next if reflection.nil? || !(reflection.klass <= base_model)

                loaded = records.flat_map { |record| record.association(name).target }
                Inheritance::Expander.new(reflection.klass, loaded.compact, targets).call
              end
            end
          end

          def preloaded_association_names
            list = preload_values + (eager_loading? ? [] : includes_values)
            list.flat_map { |entry| entry.is_a?(Hash) ? entry.keys : entry }
          end
```

`preload_associations` is public on `ActiveRecord::Relation` (`relation.rb:1321`, above the `protected` at `:1330`), but keeping the override private here is fine because AR only ever calls it on `self` from `exec_queries`.

`flat_map` handles both collection targets (an array, flattened) and singular ones (the record itself), and `compact` drops unloaded `belongs_to` targets.

- [ ] **Step 5: Drop the association scope**

Replace `spec/models/author.rb` with:

```ruby
class Author < ActiveRecord::Base
  has_many :activities
  has_many :posts
end
```

The `-> { cast_records }` scope existed to get correct classes through the association, which now happens unconditionally. Leaving it would force every `author.activities` query to pay for outer joins.

- [ ] **Step 6: Run the new tests**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb -e 'on associations'`
Expected: PASS, 4 examples.

- [ ] **Step 7: Run the full suite**

Run: `bundle exec rspec`
Expected: 0 failures, 2 pending.

- [ ] **Step 8: Commit**

```bash
git add lib spec
git commit -m "Propagate expansion through preloaded associations

Merging an expand_records relation for another model now records the
request keyed by that model, and the preloader applies it to the scope
that actually loads it. Authors no longer need a cast_records
association scope to get correctly classed activities."
```

---

## Final verification

- [ ] **Step 1: Confirm no references to removed API remain**

Run: `grep -rn 'cast_records\|cast_record\b\|_auto_cast\|auto_cast_column_name' lib spec README.md`
Expected: no output.

- [ ] **Step 2: Run the whole suite**

Run: `bundle exec rspec`
Expected: 0 failures, 2 pending — only `enum_set_spec.rb:58` and `insert_all_spec.rb:80`, both unrelated to inheritance. The inheritance file must have **0 pending**, since the `xit` at the old line 392 became a real example in Task 4.

- [ ] **Step 3: Verify the design's query-count claim end to end**

Run: `bundle exec rspec spec/tests/table_inheritance_spec.rb -e 'uses one query per table when expanding through an association'`
Expected: PASS — 4 queries for `Author.includes(:activities).merge(Activity.expand_records)`.

- [ ] **Step 4: Update the design spec status**

Change the `Status:` line at the top of `docs/superpowers/specs/2026-08-06-inheritance-rework-design.md` to `implemented`, then commit:

```bash
git add docs/superpowers/specs/2026-08-06-inheritance-rework-design.md
git commit -m "Mark the inheritance rework spec as implemented"
```
