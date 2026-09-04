---
layout: docs-home
title: Torque PostgreSQL
toc: false

meta:
  title: PostgreSQL
  repository: crashtech/torque-postgresql
  version: 4.1.1
  footer:
    - Torque PostgreSQL is MIT licensed
    - Requires Ruby 3.2+ and Rails 8.0+

# The compatibility matrix from the README, newest first. The home page turns
# this into the Rails selector that rewrites the gem line.
versions:
  - { rails: '8.1', gem: '~> 4.1' }
  - { rails: '8.0', gem: '~> 4.0' }
  - { rails: '7.2', gem: '~> 3.4' }
  - { rails: '7.1', gem: '~> 3.3' }
  - { rails: '7.0', gem: '~> 3.0' }
  - { rails: '6.1', gem: '~> 2.0.4' }
  - { rails: '6.0', gem: '~> 2.0' }

# Sections shown in the top bar, the sidebar, and the home page link strips.
# A page without a `url` renders as a dimmed, non-clickable entry rather than
# a broken link.
nav:
  - title: Getting Started
    id: getting-started
    pages:
      - title: Installation
        url: /getting-started/installation/
      - title: Configuring
        url: /getting-started/configuring/

  - title: Data Types
    id: data-types
    note: Better data representation that leads to easier-to-maintain codebases
    pages:
      - title: Box
        url: /data-types/box/
      - title: Circle
        url: /data-types/circle/
      - title: Composite
        url: /data-types/composite/
      - title: Date/Time Range
        url: /data-types/date-time-range/
      - title: Enum
        url: /data-types/enum/
      - title: EnumSet
        url: /data-types/enum-set/
      - title: Interval
        url: /data-types/interval/
      - title: Line
        url: /data-types/line/
      - title: LTree
        url: /data-types/ltree/
      - title: Segment
        url: /data-types/segment/
      - title: Struct
        url: /data-types/struct/

  - title: Modeling
    id: modeling
    note: Behaviors once impossible now made available and without any surprises
    pages:
      - title: Belongs to Many
        url: /modeling/belongs-to-many/
      - title: Dynamic Attributes
        url: /modeling/dynamic-attributes/
      - title: Has Many
        url: /modeling/has-many/
      - title: Inherited Tables
        url: /modeling/inherited-tables/
      - title: Insert All
        url: /modeling/insert-all/

  - title: Querying
    id: querying
    note: Things that make the developer life easier without breaking a sweat
    pages:
      - title: Arel
        url: /querying/arel/
      - title: Auxiliary Statements
        short: CTEs
        url: /querying/auxiliary-statements/
      - title: Buckets
        url: /querying/buckets/
      - title: Distinct On
        url: /querying/distinct-on/
      - title: Full-Text Search
        url: /querying/full-text-search/
      - title: Join Series
        url: /querying/join-series/
      - title: Predicate Builder
        url: /querying/predicate-builder/

  - title: Experimental
    id: experimental
    note: Newer ground - the API may still move between minor versions.
    pages:
      - title: Multiple Schemas
        url: /experimental/multiple-schemas/
      - title: Versioned Commands
        short: Versioned Cmds
        url: /experimental/versioned-commands/
---

<section class="hero tui-grid tui-grid-md-2 tui-items-center tui-gap-8">
  <div>
    <h1>The seamless <span class="ror">RoR</span> interfaces to empower your <span class="accent">PG</span> queries.</h1>
    <h1>Unlock these advanced features under the same <span class="ror">DSL</span></h1>
    <div class="tui-hero-actions">
      <a class="tui-button tui-button-primary" href="/postgresql/getting-started/installation/">Read the docs</a>
      <a class="tui-button tui-button-outline" href="#install">Install</a>
    </div>
  </div>
  <img src="/assets/images/pg.svg" alt="TORQUE POSTGRESQL" style="margin-block-start: -10%;" />
</section>

<section class="tui-grid tui-grid-md-2 tui-gap-6 tui-mb-12 tui-items-start" id="install">
  <div class="tui-card">
    <div class="tui-card-header"><h2>Description</h2></div>
    <div class="tui-card-body">
      <p><strong>torque-postgresql</strong> is a plugin that enhances Ruby on Rails, enabling easy
        access to existing PostgreSQL advanced resources, such as data types and query statements.
        Its features are designed to be similar to Rails architecture and work as smoothly as
        possible.</p>
      <p>Fully compatible with <strong>schema.rb</strong> and 100% plug-and-play, with optional
        configurations, so that it can be adapted to your project's design pattern.</p>
    </div>
  </div>

  <div class="tui-card">
    <div class="tui-card-header"><h2>Installation</h2></div>
    <div class="tui-card-body">
      <p class="tui-text-2">To install <strong>torque-postgresql</strong>, pick the version of Rails you
        are running:</p>
      <div class="pill tui-flex tui-gap-2 tui-items-stretch">
        <div class="tui-input-group tui-flex-1">
          <span class="tui-input-addon"><code data-gem-line><span class="cmd">gem</span> <span class="str">'torque-postgresql'</span>, <span class="str">'~&gt; 4.1'</span></code></span>
          {%- include copy-button.html label="Copy the gem line" -%}
        </div>
        <select class="rails" data-rails aria-label="Rails version">
          {%- for pair in page.versions %}
            <option value="{{ pair.gem }}">Rails {{ pair.rails }}</option>
          {%- endfor %}
        </select>
      </div>

      <p class="tui-text-2">Then run:</p>
      <div class="pill tui-input-group">
        <span class="tui-input-addon"><code>$ bundle</code></span>
        {%- include copy-button.html label="Copy the bundle command" -%}
      </div>

      <p class="tui-text-2">Or, without a Gemfile:</p>
      <div class="pill tui-input-group">
        <span class="tui-input-addon"><code>$ gem install torque-postgresql</code></span>
        {%- include copy-button.html label="Copy the install command" -%}
      </div>
    </div>
  </div>
</section>
