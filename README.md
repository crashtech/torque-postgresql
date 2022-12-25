
# Torque PostgreSQL

[![CircleCI](https://circleci.com/gh/crashtech/torque-postgresql/tree/master_v2.svg?style=svg)](https://circleci.com/gh/crashtech/torque-postgresql/tree/master_v2)
[![Code Climate](https://codeclimate.com/github/crashtech/torque-postgresql/badges/gpa.svg)](https://codeclimate.com/github/crashtech/torque-postgresql)
[![Gem Version](https://badge.fury.io/rb/torque-postgresql.svg)](https://badge.fury.io/rb/torque-postgresql)
<!--([![Test Coverage](https://codeclimate.com/github/crashtech/torque-postgresql/badges/coverage.svg)](https://codeclimate.com/github/crashtech/torque-postgresql/coverage))-->
<!--([![Dependency Status](https://gemnasium.com/badges/github.com/crashtech/torque-postgresql.svg)](https://gemnasium.com/github.com/crashtech/torque-postgresql))-->

* [Wiki](https://github.com/crashtech/torque-postgresql/wiki)
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

* [Configuring](https://github.com/crashtech/torque-postgresql/wiki/Configuring)

## Core Extensions

* [~~Range~~](https://github.com/crashtech/torque-postgresql/wiki/Range) (DEPRECATED)

## Data types

* [Box](https://github.com/crashtech/torque-postgresql/wiki/Box)
* [Circle](https://github.com/crashtech/torque-postgresql/wiki/Circle)
* [Date/Time Range](https://github.com/crashtech/torque-postgresql/wiki/Date-Time-Range)
* [Enum](https://github.com/crashtech/torque-postgresql/wiki/Enum)
* [EnumSet](https://github.com/crashtech/torque-postgresql/wiki/Enum-Set)
* [Interval](https://github.com/crashtech/torque-postgresql/wiki/Interval)
* [Line](https://github.com/crashtech/torque-postgresql/wiki/Line)
* [Segment](https://github.com/crashtech/torque-postgresql/wiki/Segment)

## Querying

* [Arel](https://github.com/crashtech/torque-postgresql/wiki/Arel)
* [Auxiliary Statements](https://github.com/crashtech/torque-postgresql/wiki/Auxiliary-Statements)
* [Belongs to Many](https://github.com/crashtech/torque-postgresql/wiki/Belongs-to-Many)
* [Distinct On](https://github.com/crashtech/torque-postgresql/wiki/Distinct-On)
* [Dynamic Attributes](https://github.com/crashtech/torque-postgresql/wiki/Dynamic-Attributes)
* [Has Many](https://github.com/crashtech/torque-postgresql/wiki/Has-Many)
* [Inherited Tables](https://github.com/crashtech/torque-postgresql/wiki/Inherited-Tables)
* [Insert All](https://github.com/crashtech/torque-postgresql/wiki/Insert-All)
* [Multiple Schemas](https://github.com/crashtech/torque-postgresql/wiki/Multiple-Schemas)

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
