<a href="https://torque.dev/postgresql/">
  <img src="./docs/assets/images/github.png" alt="Torque PostgreSQL - Advanced PG features in a seamlessly RoR interface" />
</a>

[![CircleCI](https://dl.circleci.com/status-badge/img/gh/crashtech/torque-postgresql/tree/master.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/crashtech/torque-postgresql/tree/master)
[![Code Climate](https://codeclimate.com/github/crashtech/torque-postgresql/badges/gpa.svg)](https://codeclimate.com/github/crashtech/torque-postgresql)
[![Gem Version](https://badge.fury.io/rb/torque-postgresql.svg)](https://badge.fury.io/rb/torque-postgresql)
<!--([![Test Coverage](https://codeclimate.com/github/crashtech/torque-postgresql/badges/coverage.svg)](https://codeclimate.com/github/crashtech/torque-postgresql/coverage))-->

* [Docs](https://torque.dev/postgresql/)
* [Bugs](https://github.com/crashtech/torque-postgresql/issues)
* [TODO](https://github.com/crashtech/torque-postgresql/wiki/TODO)

# Description
`torque-postgresql` is a plugin that enhances Ruby on Rails enabling easy access to existing PostgreSQL advanced resources, such as data types and query statements. Its features are designed to be similar to Rails architecture and work as smoothly as possible.

Fully compatible with `schema.rb` and 100% plug-and-play, with optional configurations, so that it can be adapted to your project's design pattern.

# Installation

To install torque-postgresql you need to add the following to your Gemfile:
```ruby
gem 'torque-postgresql', '~> 2.0'   # For Rails >= 6.0 < 6.1
gem 'torque-postgresql', '~> 2.0.4' # For Rails >= 6.1
gem 'torque-postgresql', '~> 3.0'   # For Rails >= 7.0 < 7.1
gem 'torque-postgresql', '~> 3.3'   # For Rails >= 7.1 < 7.2
gem 'torque-postgresql', '~> 3.4'   # For Rails >= 7.2 < 8.0
gem 'torque-postgresql', '~> 4.0'   # For Rails >= 8.0 < 8.1
gem 'torque-postgresql', '~> 4.1'   # For Rails >= 8.1
```

Also, run:

```
$ bundle
```

Or, for non-Gemfile related usage, simply:

```
gem install torque-postgresql
```

# Usage
These are the currently available features:

* [Configuring](https://torque.dev/postgresql/getting-started/configuring/)

## Data types

* [Box](https://torque.dev/postgresql/data-types/box/)
* [Circle](https://torque.dev/postgresql/data-types/circle/)
* [Composite](https://torque.dev/postgresql/data-types/composite/)
* [Date/Time Range](https://torque.dev/postgresql/data-types/date-time-range/)
* [Enum](https://torque.dev/postgresql/data-types/enum/)
* [EnumSet](https://torque.dev/postgresql/data-types/enum-set/)
* [Interval](https://torque.dev/postgresql/data-types/interval/)
* [Line](https://torque.dev/postgresql/data-types/line/)
* [LTree](https://torque.dev/postgresql/data-types/ltree/)
* [Segment](https://torque.dev/postgresql/data-types/segment/)
* [Struct](https://torque.dev/postgresql/data-types/struct/)

## Querying

* [Arel](https://torque.dev/postgresql/querying/arel/)
* [Auxiliary Statements](https://torque.dev/postgresql/querying/auxiliary-statements/)
* [Belongs to Many](https://torque.dev/postgresql/modeling/belongs-to-many/)
* [Distinct On](https://torque.dev/postgresql/querying/distinct-on/)
* [Dynamic Attributes](https://torque.dev/postgresql/modeling/dynamic-attributes/)
* [Has Many](https://torque.dev/postgresql/modeling/has-many/)
* [Inherited Tables](https://torque.dev/postgresql/modeling/inherited-tables/)
* [Insert All](https://torque.dev/postgresql/modeling/insert-all/)
* [Predicate Builder](https://torque.dev/postgresql/querying/predicate-builder/)
* [Full‐Text Search](https://torque.dev/postgresql/querying/full-text-search/)
* [Join Series](https://torque.dev/postgresql/querying/join-series/)
* [Buckets](https://torque.dev/postgresql/querying/buckets/)

## Experimental

* [Multiple Schemas](https://torque.dev/postgresql/experimental/multiple-schemas/)
* [Versioned Commands (Views, Functions, Types, Triggers)](https://torque.dev/postgresql/experimental/versioned-commands/)

# How to Contribute

To start, simply fork the project, create a `.env` file following this example:

```
DATABASE_URL="postgres://USER:PASSWORD@localhost/DATABASE"
```

Run local tests using:
```
$ bundle install
$ bundle exec rake spec
```
Finally, fix and send a pull request.

## License

Copyright © 2017- Carlos Silva. See [The MIT License](MIT-LICENSE) for further details.
