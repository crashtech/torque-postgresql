---
title: Multiple Schemas
section: experimental
description: Add smooth support to managing and utilizing multiple schemas in your
  application.
---

Add smooth support to managing and utilizing multiple schemas in your application. It works incredibly nicely with [Inherited Tables](/postgresql/modeling/inherited-tables/) and it's part of a larger feature for a better multi-tenancy application. [PostgreSQL Docs](https://www.postgresql.org/docs/current/ddl-schemas.html)

## Configuration

This feature works with a [whitelist](/postgresql/getting-started/configuring/#schemas.whitelist)/[blacklist](/postgresql/getting-started/configuring/#schemas.blacklist) set of schemas, that filters, in a LIKE manner, the ones that will be present in the schema. These lists are extremely important so that it can not only work properly, but also interact with other features from this gem.

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  schemas:
    whitelist: ['internal']
    blacklist: ['external']

# OR a list of items, that also demonstrates the LIKE behavior
default: &default
  schemas:
    whitelist:
      - internal_%
```

This can also be configured exclusively for Torque, in your `application.rb` or similar place.

```ruby
Torque::PostgreSQL.configure do |c|
  c.schemas.whitelist << 'internal'
  c.schemas.blacklist += %w[external other]
end
```

## Migration

Once you have stipulated which schemas will be supported in the configuration, you can now create a migration that creates them.

```ruby
create_schema :internal
```

## Models

There are 2 ways to set a model's schema. You can define it directly or use the module as the reference for all its models' schemas.

```ruby
# Directly on the model
module Internal
  class User < ActiveRecord::Base
    self.schema = 'internal'
  end
end

# Indirect using the module
module Internal
  def self.schema
    'internal'
  end

  class User < ActiveRecord::Base
  end
end
```
