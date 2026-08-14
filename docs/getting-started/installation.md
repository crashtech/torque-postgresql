---
title: Installation
section: getting-started
description: >-
  Add torque-postgresql to a Rails application, and pick the release that
  matches the version of Rails you are on.
---

`torque-postgresql` is a plugin that enhances Ruby on Rails, enabling easy access to existing
PostgreSQL advanced resources, such as data types and query statements. It is 100% plug-and-play:
once the gem is in your Gemfile there is nothing to configure before you start using it.

## Requirements

Ruby {{ site.ruby_version }} or newer, Rails {{ site.rails_version }}, and the `pg` adapter.
Every feature is built on PostgreSQL's own capabilities, so the database has to be PostgreSQL —
there is no fallback for other adapters.

## Add the gem

Each release line tracks a version of Rails. Add the one that matches your application:

```ruby
{% for pair in site.data.versions -%}
gem 'torque-postgresql', '{{ pair.gem }}'   # For Rails {{ pair.rails }}
{% endfor -%}
```

Then install it:

```bash
bundle install
```

Or, for use outside a Gemfile:

```bash
gem install torque-postgresql
```

## What you get

Nothing changes in how you write Rails. The gem extends the PostgreSQL adapter, the schema dumper,
and Active Record's query interface in place, so migrations, `schema.rb`, models and scopes keep
the shape you already know — they simply understand more.

From here, the [data types]({{ site.baseurl }}/data-types/composite/) cover what a column can
hold, and [querying]({{ site.baseurl }}/querying/arel/) covers what you can ask of it. Every
default the gem sets can be changed in [configuring]({{ site.baseurl }}/getting-started/configuring/).
