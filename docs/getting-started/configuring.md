---
title: Configuring
section: getting-started
description: 'Some resources may have extra configurations that can be set in your
  application.rb as following: Torque::PostgreSQL.configure do |c| c.enum.base_method
  = :pg_enum end'
---

Some resources may have extra configurations that can be set in your `application.rb` as following:
```ruby
# application.rb
Torque::PostgreSQL.configure do |c|
  c.enum.base_method = :pg_enum
end
```

## General configurations {#general}

These are the keys available to configure general features:

<a name="eager_load"></a>`eager_load` Set if any information that requires querying and searching or collecting information should be eager loaded. This automatically changes when Rails' same configuration is set to true.  
Default value: `false`

<a name="join_series"></a>`join_series` Add support for joining any query or association with a generated series, through the `join_series` method on relations.  
Default value: `true`

<a name="buckets"></a>`buckets` Add support for querying and calculating histogram buckets, through the `buckets` method on relations.  
Default value: `true`

<a name="irregular_models"></a>`irregular_models` Set a list of irregular model names when associated with table names. It uses the `'table_name' => 'ModelName'` format. This is widely used for inheritance because record types need to be associated with a model class.  
Default value: `{}`

## Associations configurations {#associations}

These are the keys available to configure associations features:

<a name="associations.belongs_to_many_required_by_default"></a>`associations.belongs_to_many_required_by_default` Define if `belongs_to_many` associations are marked as required by default. `false` means that no validation will be performed.  
Default value: `false`

<!--
<a name="associations.optimize_for_binds"></a>`associations.optimize_for_binds` Define if `belongs_to_many` and `has_many array: true` will use `ANY($1)` when possible to reduce the number of binds (and the number of necessary prepared statements).  
Default value: `false`
-->

## Schemas configurations {#schemas}

These are the keys available to configure schemas features:

<a name="schemas.enabled"></a>`schemas.enabled` Enables schemas handler by this gem, not Rails's own implementation.  
Default value: `true`

<a name="schemas.blacklist"></a>`schemas.blacklist` Defines a list of LIKE-based schemas to not consider for a multiple schema database. This is also available on `config/database.yml` as `schemas` and nested to it, `blacklist`.  
Default value: `['information_schema', 'pg_%']`

<a name="schemas.whitelist"></a>`schemas.whitelist` Defines a list of LIKE-based schemas to consider for a multiple schema database. This is also available on `config/database.yml` as `schemas` and nested to it, `whitelist`.  
Default value: `['public']`

## Auxiliary statements configurations {#auxiliary_statement}

These are the keys available to configure Auxiliary statements features:

<a name="auxiliary_statement.enabled"></a>`auxiliary_statement.enabled` Enables auxiliary statements handler by this gem, not Rails's own implementation.  
Default value: `true`

<a name="auxiliary_statement.send_arguments_key"></a>`auxiliary_statement.send_arguments_key` Define the key that is used on auxiliary statements to send extra arguments to format string or send on a proc.  
Default value: `:args`

<a name="auxiliary_statement.exposed_class"></a>`auxiliary_statement.exposed_class` Stipulate a class name (which may contain namespace) that exposes the auxiliary statement in order to perform detached CTEs.  
Default value: `'TorqueCTE'`

<a name="auxiliary_statement.exposed_recursive_class"></a>`auxiliary_statement.exposed_recursive_class` Stipulate a class name (which may contain namespace) that exposes the recursive auxiliary statement in order to perform detached CTEs.  
Default value: `'TorqueRecursiveCTE'`

## Enum configurations {#enum}

These are the keys available to configure Enum features:

<a name="enum.enabled"></a>`enum.enabled` Enables enum handler by this gem, not Rails's own implementation.  
Default value: `true`

<a name="enum.base_method"></a>`enum.base_method` The name of the method to be used on any ActiveRecord::Base to initialize model-based enum features.  
Default value: `:torque_enum`

<a name="enum.set_method"></a>`enum.set_method` The name of the method to be used on any ActiveRecord::Base to initialize model-based enum set features.  
Default value: `:torque_enum_set`

<a name="enum.save_on_bang"></a>`enum.save_on_bang` Indicates if bang methods like 'disabled!' should update the record on database or not.  
Default value: `true`

<a name="enum.raise_conflicting"></a>`enum.raise_conflicting` Indicates if it should raise errors when a generated method would conflict with an existing one.  
Default value: `false`

<a name="enum.namespace"></a>`enum.namespace` Specify the namespace of each enum-type of value, such as `::Enum::Roles`.  
Default value: `::Enum`

<a name="enum.i18n_scopes"></a>`enum.i18n_scopes` Specify the scopes for I18n translations.  
Default value:
```ruby
[ 'activerecord.attributes.%{model}.%{attr}.%{value}',
  'activerecord.attributes.%{attr}.%{value}',
  'activerecord.enums.%{type}.%{value}',
  'enum.%{type}.%{value}',
  'enum.%{value}' ]
```

<a name="enum.i18n_type_scopes"></a>`enum.i18n_type_scopes` Specify the scopes for I18n translations, detached from model.  
Default value: `# Same list as before but without items that have ${attr} or %{model}`

## Geometry configurations {#geometry}

These are the keys available to configure geometries features:

<a name="geometry.enabled"></a>`geometry.enabled` Enables geometry handler by this gem, not Rails's own implementation.  
Default value: `true`

<a name="geometry.point_class"></a>`geometry.point_class` Define the class that will be handling Point data types after decoding it. Any class provided here must respond to 'x', and 'y'.  
Default value: `ActiveRecord::Point`

<a name="geometry.box_class"></a>`geometry.box_class` Define the class that will be handling Box data types after decoding it. Any class provided here must respond to 'x1', 'y1', 'x2', and 'y2'.  
Default value: `nil # Which will define an internal Circle class`

<a name="geometry.circle_class"></a>`geometry.circle_class` Define the class that will be handling Circle data types after decoding it. Any class provided here must respond to 'x', 'y', and 'r'.  
Default value: `nil # Which will define an internal Box class`

<a name="geometry.line_class"></a>`geometry.line_class` Define the class that will be handling Line data types after decoding it. Any class provided here must respond to 'a', 'b', and 'c'.  
Default value: `nil # Which will define an internal Line class`

<a name="geometry.segment_class"></a>`geometry.segment_class` Define the class that will be handling Segment data types after decoding it. Any class provided here must respond to 'x1', 'y1', 'x2', and 'y2'.  
Default value: `nil # Which will define an internal Segment class`

## Inheritance configurations {#inheritance}

These are the keys available to configure Inheritance features:

<a name="inheritance.inverse_lookup"></a>`inheritance.inverse_lookup` Define the lookup of models from their given name to be inverted, which means that they are going to form the last namespaced one to the most namespaced one. If you prefer `User::Role` instead of `UserRole` as model name, set this to `false` to improve performance.  
Default value: `true`

<a name="inheritance.record_class_column_name"></a>`inheritance.record_class_column_name` Determines the name of the column used to collect the table of each record. When the table has inheritance tables, this column will return the name of the table that actually holds the record.  
Default value: `:_record_class`

## Struct configurations {#struct}

These are the keys available to configure Struct features:

<a name="struct.enabled"></a>`struct.enabled` Enables the JSON(B) columns backed by ActiveModel classes handler.  
Default value: `true`

<a name="struct.base_method"></a>`struct.base_method` The name of the method to be used on any ActiveRecord::Base to initialize model-based struct features.  
Default value: `:struct_for`

<a name="struct.default_strict"></a>`struct.default_strict` Whether struct classes reject properties that they don't declare. It can be changed per class, with `self.strict =`, or per column, with the `strict` option.  
Default value: `true`

## Composite configurations {#composite}

These are the keys available to configure Composite features:

<a name="composite.enabled"></a>`composite.enabled` Enables the composite types handler by this gem, which loads the types from the database, backs their columns with ActiveModel classes, and adds `create_composite_type` and `change_composite_type` to migrations.  
Default value: `true`

<a name="composite.namespace"></a>`composite.namespace` Specify the namespace of each composite-type class, such as `::Composite::Address`. Classes that are not defined there are created on demand, which means a composite type never needs a class of its own to work.  
Default value: `::Composite`

<a name="composite.irregular_types"></a>`composite.irregular_types` Set a list of irregular class names when associated with composite types. It uses the `'type_name' => 'ClassName'` format, and it takes precedence over the namespace lookup.  
Default value: `{}`

## Period configurations {#period}

These are the keys available to configure Period features:

<a name="period.enabled"></a>`period.enabled` Enables the period handler provided by this gem.  
Default value: `true`

<a name="period.base_method"></a>`period.base_method` The name of the method to be used on any ActiveRecord::Base to initialize model-based period features.  
Default value: `:period_for`

<a name="period.auto_threshold"></a>`period.auto_threshold` The default name for a threshold attribute, which will automatically enable threshold features.  
Default value: `:threshold`

<a name="period.method_names"></a>`period.method_names` Define the list of methods that will be created by default while setting up a new period field. Note that `%s` will be replaced by the name of the filter.  
Default value:
```ruby
{ current_on:            '%s_on',
  current:               'current_%s',
  not_current:           'not_current_%s',
  containing:            '%s_containing',
  not_containing:        '%s_not_containing',
  overlapping:           '%s_overlapping',
  not_overlapping:       '%s_not_overlapping',
  starting_after:        '%s_starting_after',
  starting_before:       '%s_starting_before',
  finishing_after:       '%s_finishing_after',
  finishing_before:      '%s_finishing_before',

  real_containing:       '%s_real_containing',
  real_overlapping:      '%s_real_overlapping',
  real_starting_after:   '%s_real_starting_after',
  real_starting_before:  '%s_real_starting_before',
  real_finishing_after:  '%s_real_finishing_after',
  real_finishing_before: '%s_real_finishing_before',

  containing_date:       '%s_containing_date',
  not_containing_date:   '%s_not_containing_date',
  overlapping_date:      '%s_overlapping_date',
  not_overlapping_date:  '%s_not_overlapping_date',
  real_containing_date:  '%s_real_containing_date',
  real_overlapping_date: '%s_real_overlapping_date',

  current?:              'current_%s?',
  current_on?:           'current_%s_on?',
  start:                 '%s_start',
  finish:                '%s_finish',
  real:                  'real_%s',
  real_start:            '%s_real_start',
  real_finish:           '%s_real_finish',              }
```

<a name="period.direct_method_names"></a>`period.direct_method_names` If the period is marked as direct access, without the field name, then these method names will replace the default ones.  
Default value:
```ruby
{ current_on:          'happening_in',
  containing:          'during',
  not_containing:      'not_during',
  real_containing:     'real_during',

  containing_date:     'during_date',
  not_containing_date: 'not_during_date',

  current_on?:         'happening_in?',
  start:               'start_at',
  finish:              'finish_at',
  real:                'real_time',
  real_start:          'real_start_at',
  real_finish:         'real_finish_at',   }
```

## Interval configurations {#interval}

These are the keys available to configure Interval features:

<a name="interval.enabled"></a>`interval.enabled` Enables interval handler by this gem, not Rails's own implementation.  
Default value: `true`

## LTree configurations {#ltree}

These are the keys available to configure LTree features:

<a name="ltree.enabled"></a>`ltree.enabled` Enables the ltree and lquery data types handler by this gem.  
Default value: `true`

<a name="ltree.sanitize"></a>`ltree.sanitize` A hash of replacements applied to every label provided by the application before it is sent to the database, so that a source that does not satisfy PostgreSQL's rules on its own can still be used. Dashes, for example, are only accepted as of PostgreSQL 16, so `{ '-' => '_' }` turns them into underscores and `{ '-' => '' }` drops them. It never applies to values read from the database.  
Default value: `nil`

<a name="ltree.compatible_method"></a>`ltree.compatible_method` The name of a method that, whenever the given object responds to it, is used to translate that object into a path or a pattern. It lets any class be used wherever one is expected, on assignment, on a condition, and while comparing one path to another. Set it to `nil` to turn the behavior off.  
Default value: `:to_tree_path`

## Arel configurations {#arel}

These are the keys available to configure Arel features:

<a name="arel.expose_function_helper_on"></a>`arel.expose_function_helper_on` When provided, the initializer will expose the Arel function helper (FN) on the given module. Recommended `'PG::Fn'`.  
Default value: `nil`

<a name="arel.infix_operators"></a>`arel.infix_operators` List of Arel INFIX operators that will be made available for using as methods on Arel::Nodes::Node and Arel::Attribute. The pairs are `method_name` and `operator`.  
Default value:
```ruby
{ 'contained_by'        => '<@',
  'has_key'             => '?',
  'has_all_keys'        => '?&',
  'has_any_keys'        => '?|',
  'strictly_left'       => '<<',
  'strictly_right'      => '>>',
  'doesnt_right_extend' => '&<',
  'doesnt_left_extend'  => '&>',
  'adjacent_to'         => '-|-',
  'matches_lquery'      => '~',
  'matches_any_lquery'  => '?' }
```

## Full-text search configurations {#full_text_search}

These are the keys available to configure Full-Text Search features:

<a name="full_text_search.enabled"></a>`full_text_search.enabled` Enables full text search handler by this gem.  
Default value: `true`

<a name="full_text_search.base_method"></a>`full_text_search.base_method` The name of the method to be used on any ActiveRecord::Base to initialize model-based full text search features.  
Default value: `:torque_search_for`

<a name="full_text_search.default_language"></a>`full_text_search.default_language` Defines the default language when generating search vector columns.  
Default value: `'english'`

<a name="full_text_search.default_mode"></a>`full_text_search.default_mode` Defines the default mode to be used when generating full text search queries. It can be `:default` (`to_tsquery`), `:phrase` (`phraseto_tsquery`), `:plain` (`plainto_tsquery`), or `:web` (`websearch_to_tsquery`).  
Default value: `:phrase`

<a name="full_text_search.default_index_type"></a>`full_text_search.default_index_type` Defines the default index type to be used when creating search vector. It still requires that the column requests an index.  
Default value: `:gin`

## Predicate builder configurations {#predicate_builder}

These are the keys available to configure Predicate Builder features:

<a name="predicate_builder.enabled"></a>`predicate_builder.enabled` List which handlers are enabled by default. Possible values are: `regexp`, `arel_attribute`, `enumerator_lazy`.  
Default value: `%i[regexp arel_attribute enumerator_lazy]`

<a name="predicate_builder.handle_array_attributes"></a>`predicate_builder.handle_array_attributes` When active, values provided to array attributes will be handled more friendly. It will use the `ANY` operator on an equality check and overlaps when the given value is an array.  
Default value: `false`

<a name="predicate_builder.lazy_timeout"></a>`predicate_builder.lazy_timeout` Make sure that the predicate builder will not spend more than this many seconds trying to produce the underlying array.  
Default value: `0.02`

<a name="predicate_builder.lazy_limit"></a>`predicate_builder.lazy_limit` Since lazy array is uncommon, it is better to limit the number of entries we try to pull so we don't cause a timeout or a long wait iteration.  
Default value: `2_000`

## Versioned commands configurations {#versioned_commands}

These are the keys available to configure [versioned commands](/postgresql/experimental/versioned-commands/):

<a name="versioned_commands.enabled"></a>`versioned_commands.enabled` Enables managing `views`, `functions`, `triggers`, and non-enum `types` from versioned `.sql` migrations. This is opt-in because it changes how migrations behave and adds an extra schema table.  
Default value: `false`

<a name="versioned_commands.types"></a>`versioned_commands.types` The list of commands that are versioned by this feature.  
Default value: `%i[function type view trigger]`

<a name="versioned_commands.table_name"></a>`versioned_commands.table_name` The name of the table that inherits from `schema_migrations` and stores the list of versioned commands that have been executed.  
Default value: `'schema_versioned_commands'`
