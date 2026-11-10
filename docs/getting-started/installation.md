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

Ruby 3.2 or newer and the `pg` adapter. The newest gem line tracks Rails 8.x; older lines cover Rails 6.0 through 7.2, per the table below.
Every feature is built on PostgreSQL's own capabilities, so the database has to be PostgreSQL —
there is no fallback for other adapters.

## Add the gem

Each release line tracks a version of Rails. Add the one that matches your application:

```ruby
{% assign home = site.pages | where: 'docs', page.docs | where: 'layout', 'docs-home' | first -%}
{% assign widest = 0 -%}
{% for pair in home.versions -%}
  {%- if pair.gem.size > widest %}{% assign widest = pair.gem.size %}{% endif -%}
{% endfor -%}
{% for pair in home.versions -%}
{%- assign pad_size = widest | minus: pair.gem.size -%}
{%- assign pad = '          ' | slice: 0, pad_size -%}
gem 'torque-postgresql', '{{ pair.gem }}'{{ pad }}   # For Rails {{ pair.rails }}
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

From here, the [data types](/postgresql/data-types/composite/) cover what a column can
hold, and [querying](/postgresql/querying/arel/) covers what you can ask of it. Every
default the gem sets can be changed in [configuring](/postgresql/getting-started/configuring/).
