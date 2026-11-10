---
title: Insert All
section: modeling
description: Small extension to the upsert_all method to support the WHERE filtering
  which records will be updated.
---

Small extension to the `upsert_all` method to support `WHERE` filtering of which records will be updated. [PostgreSQL Docs (`condition` clause)](https://www.postgresql.org/docs/9.6/sql-insert.html#SQL-ON-CONFLICT)

## How to

When executing your `upsert_all` operation, just add the extra `where:` keyword argument with the desired SQL expression.
```ruby
Tag.upsert_all([{ id: 1, name: 'Tag 10' }, { id: 2, name: 'Tag 20' }], where: 'tags.id >= 2')
```

So far it does not support the use of scopes or model-based queries like `Tag.where(enabled: true)`.

## When to use

The best place to use such a feature is when your table is set to use [Optimistic Locking](https://api.rubyonrails.org/classes/ActiveRecord/Locking/Optimistic.html). In one operation you can insert multiple records, guarantee that stale objects are not updated, and get the id of those that were updated (then figure out those that were not).
```ruby
class Tag < ActiveRecord::Base
  self.locking_column = :version
end

entries = [{ id: 1, name: 'Tag 10' }, { id: 2, name: 'Tag 20' }]

result = Tag.upsert_all(entries, where: 'tags.version <= excluded.version')
updated = result.rows.flatten.map(&:to_i)                      # [1] the ids of the records successfully updated
entries.map { |entry| entry[:id] } - updated                   # [2] the ids of the records that were not updated
```
