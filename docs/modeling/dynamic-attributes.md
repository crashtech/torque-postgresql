---
title: Dynamic Attributes
section: modeling
description: This method allows defining a conditional value that, if present in the
  result set, don't do anything.
---

This method allows defining a conditional value that, if present in the result set, does nothing. But, if it was not available, it will call its block in order to try returning the expected value. This feature is great when used together with [Auxiliary Statements](/postgresql/querying/auxiliary-statements/).

## Configurating

In any model, you just need to call `dynamic_attribute` method, passing a name for it and the block that will be called in case the attribute is not present.

```ruby
# models/user.rb
class User < ActiveRecord::Base
  dynamic_attribute(:last_comment) do
    comments.order(id: :desc).first.content
  end
end
```

If the block is ever called, the value is stored for that record and won't be loaded again unless the record is wiped from ActiveRecord memory.

## Using

Using the value is as normal as accessing any other attribute from a record.

```ruby
User.first.last_comment                         # This will trigger 2 queries, one for the user and another for the attribute
User.with(:last_comment).first.last_comment     # This will trigger a single query
```
