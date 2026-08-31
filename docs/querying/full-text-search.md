---
title: Full-Text Search
section: querying
description: Full-text searching is always a cool thing to do.
---

> Sometimes `LIKE` is not enough.

Full-text searching is always a cool thing to do. However, it involves functions and operations that are generally cumbersome to write using Arel. With this feature, we can now easily set up our tables, have a proper scope, order by rank, get the rank if necessary, and it even supports dynamic language. [PostgreSQL Docs](https://www.postgresql.org/docs/current/textsearch-intro.html)

## Migration

First, it is good to set up a [generated column](https://www.postgresql.org/docs/current/ddl-generated-columns.html) with the cached vector of the records. Although not mandatory, it makes the whole implementation more rounded. Rails does provide what it calls `virtual` columns, so this is built on top of it.

```ruby
create_table :courses do |t|
  t.string :title, null: false
  t.text :description
  t.search_vector :search_vector, columns: [:title, :description]
  t.timestamps
end
```

This operation will create a proper virtual column named `search_vector` with the following function:
```sql
SETWEIGHT(TO_TSVECTOR('english', COALESCE(title, '')), 'A') ||
SETWEIGHT(TO_TSVECTOR('english', COALESCE(content, '')), 'B')
```

### Options

* `columns`: It supports a single column (`:title`), an array of columns (`[:title, :description]`), or a Hash of column and weight (`{ title: 'A', description: 'A' }`).
* `index`: If given `true`, it will set the column up with the [`full_text_search.default_index_type`](/postgresql/getting-started/configuring/#full_text_search.default_index_type).
* `language`: This is the `regconfig` used for the `to_tsvector` function. It can be a plain string of the dictionary name, or a symbol to reference another column for dynamic language support (see example below). Defaults to [`full_text_search.default_language`](/postgresql/getting-started/configuring/#full_text_search.default_language).

```ruby
# Example for a dynamic language
create_table :courses do |t|
  t.string :title, null: false
  t.text :description
  t.search_language :lang, null: false, default: 'english'
  t.column :lang, type: :regconfig, null: false, default: 'english' # Same as above
  t.search_vector :search_vector, language: :lang, columns: [:title, :description]
  t.timestamps
end
```

## Models

Then we need to enable this feature on the model, which will give a single scope `.full_text_search` capable of handling everything.

```ruby
class Course < ApplicationRecord
  torque_search_for :search_vector
end
```

### Options

* `prefix`: It allows adding a prefix to the scope name (eg, `prefix: :main` will produce `.main_full_text_search`).
* `suffix`: It allows adding a suffix to the scope name (eg, `suffix: :main` will produce `.full_text_search_main`).
* `language`: This value affects the language of the input search term. It supports a `String` as a plain value, or a `Symbol` that refers to an attribute or a public class method.
* `order`: This sets the default value for ordering the result. It can be either `true` or `:asc` for `ASC` or `:desc` for `DESC`.
* `with_rank`: This sets the default value for retrieving the result of the `RANK` function as an accessible attribute of the records. It can be `true` to add the `"rank"` attribute, or the name of the alias.
* `use_mode`: It sets the default mode of parsing the provided value. Values can be: `:default`, `:plain`, `:phrase`, or `:web`, respectively. Defaults to: `:phrase`.

```ruby
class Course < ApplicationRecord
  torque_search_for :search_vector, language: :lang    # Support for dynamic language on querying
end
```

## Querying

With the scope now set up, we can call it with several different options to find what we want.

```ruby
Course.full_text_search('Ruby')
# WHERE "courses"."search_vector" @@ PHRASETO_TSQUERY('english', 'Ruby')
```

### Options

* `order`: Indicates if the records should be sorted by the `RANK` operation. It can be either `true` or `:asc` for `ASC` or `:desc` for `DESC`.
* `rank`: If provided, it will add an extra column to the result set with the value of the calculated rank. It can be `true`, which gives a `.rank` attribute, or the alias of the attribute.
* `language`: The language to be used for the search. It supports a `String` as a plain value, or a `Symbol` that refers to an attribute or a public class method.
* `mode`: It switches between using the functions `TO_TSQUERY`, `PLAINTO_TSQUERY`, `PHRASETO_TSQUERY`, and `WEBSEARCH_TO_TSQUERY` on the provided value. Values can be: `:default`, `:plain`, `:phrase`, or `:web`, respectively. Defaults to: `:phrase`. [See more](https://www.postgresql.org/docs/current/textsearch-controls.html#TEXTSEARCH-PARSING-QUERIES).

```ruby
Course.full_text_search('Ruby', order: :desc, rank: :rank_result, language: :lang, mode: :web)
```

Produces:

```sql
SELECT "courses".*, TS_RANK("courses"."search_vector", WEBSEARCH_TO_TSQUERY(lang, 'Ruby')) AS rank_result
FROM "courses" WHERE "courses"."search_vector" @@ WEBSEARCH_TO_TSQUERY(lang, 'Ruby')
ORDER BY TS_RANK("courses"."search_vector", WEBSEARCH_TO_TSQUERY(lang, 'Ruby')) DESC
```

> Future versions will attempt to move the `tsquery` transformations into `FROM`.
