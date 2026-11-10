---
title: Auxiliary Statements
section: querying
description: Provides a way to write auxiliary statements for use in a larger query.
---

Provides a way to write auxiliary statements for use in a larger query. It's preconfigured on the model, and then can be used during the querying process. [PostgreSQL Docs](https://www.postgresql.org/docs/9.6/static/queries-with.html)

## Model

First, you need to configure the statements you want to use. These statements are very similar to scopes, but with a few more options:
```ruby
# models/user.rb
class User < ActiveRecord::Base

  auxiliary_statement :last_comment do |cte|
    cte.query Comment.distinct_on(:user_id).order(:user_id, id: :desc)
    cte.attributes content: :last_comment_content
  end

end
```

The statement is lazy loaded, so the block is called only when a query requires its usage. To configure your statement, these are the options available:

- `cte.query` The query that will be performed inside the auxiliary statement (WITH). It most likely will be one that brings extra information related to the main class, in this case, the `User` class.
- `cte.through` Define the name of the association to be used while joining the CTE to the source query.
- `cte.attributes` The list of attributes that will be exposed to the main query, and which can then be read from the fetched entries. It's read as `The column from the query => The alias exposed`. It accepts join columns in the left side as `'table.column' => 'alias'`.
- `cte.requires` Provide a list of cross-dependent auxiliary statements, where they will all be added to the source query when requested.
- `cte.join_type` The type of join between the main query and statement query. By default it's set to `:inner`, which will perform an `INNER JOIN`. The options are `:inner, :left, :right, :full`.
- `cte.join` The columns used on the join in the main query. It has similar behavior as the attributes, and it's read as `The column from the main query == The column from the statement query`. It accepts join columns in both sides as `'table.column' => 'table.column'`.

### Query option

You have to think about the query as the command that will bring the information from all the records, so don't use where or similar conditions, because they will be calculated using `join`.

For this option, you can use either a `String`, a `Proc`, or an `ActiveRecord::Relation`. For the first 2 options, you need to manually provide the table name as the first argument.

```ruby
cte.query :comments, 'SELECT * FROM comments'
cte.query :comments, -> { Comment.all }
cte.query Comment.all
```

### Accessing attributes

The class provided in the `|cte|` has many ways to facilitate accessing columns and other query stuff.

```ruby
cte.query_table          # Gives an Arel::Table of the defined statement
cte.query_table['col']   # Gives an Arel::Attributes::Attribute
cte.col('col')           # Same as the above
cte.sql('MAX(col)')      # A literal SQL string with Arel properties
```

## Querying
```ruby
with(*list)
```

Once you have configured all your statements, you can easily use them by calling `with` method.
```ruby
user = User.with(:last_comment).first
user.last_comment_content
```

You are able to use all the exposed columns set on the right side of the `attributes` configuration in other methods like `where`, `order`, `group`, etc.
```ruby
user = User.with(:last_comment).order(:last_comment_content)
```

The advantage of the String and Proc query option on an auxiliary statement is that they allow arguments, which means that they can be further configured based on what you provide on the `:args` key. **CAUTION** if you use `with` with multiple values and the `:args` for arguments, the list of arguments will be used for all `String` and `Proc` queries.

```ruby
user = User.with(:last_comment, args: {id: 1}).order(:last_comment_content)
```

You can also change the name of the key used to pass arguments using 
[`auxiliary_statement.send_arguments_key`](/postgresql/getting-started/configuring/#auxiliary_statement.send_arguments_key) config.

## Detached

Auxiliary statements can be defined detached from models, which means that you can define them anywhere, even during the Controller operations, and just provide to the Relation as `.with(detached_cte)` and making sure that both can either be automatically joined or you provided a join.

```ruby
class HomeController < ApplicationController
  def index
    last_notification = TorqueCTE.create(:last_notification) do |cte|
      cte.query Notification.distinct_on(:post_id).order(:post_id, created_at: :desc)
      cte.attributes content: :last_notification
    end

    @posts = Post.active.with(last_notification)
  end

  def show
    recipients = TorqueCTE.create(User.recipient_of(params[:id]).post_grouped)
    @notifications = Notification.from_post(params[:id]).with(recipients, select: {
      Arel.sql('array_agg("users"."email")') => :recipient_emails
    })
  end
end
```

You can change the name of the class used to create the statements in the 
[`auxiliary_statement.exposed_class`](/postgresql/getting-started/configuring/#auxiliary_statement.exposed_class) config.

## Recursive

Auxiliary statements can run with a `RECURSIVE` modifier composed of two parts. The first query, as a regular query and auxiliary statement, and then a second query, added after a `UNION`, which will occur consecutively until it does not bring any more records. [PostgreSQL Docs](https://www.postgresql.org/docs/current/queries-with.html#QUERIES-WITH-RECURSIVE) The sections below cover the model-based setup, the manual `sub_query` configuration and detached recursion.

## Recursive model

Some assumptions are made in order to simplify the process of setting up a recursive CTE.
```ruby
# models/course.rb
class Course < ActiveRecord::Base

  recursive_auxiliary_statement :all_categories do |cte|
    cte.query Category.all
    cte.attributes title: :category_title
  end

end
```

In this simple setup, where no `sub_query` is defined and using a regular `connect` option, the subquery is built from the main query, which is also altered. So, by default, the way that the 2 queries are connected is through `:id => :parent_id`. That said, the first query receives a `WHERE categories.parent_id IS NULL` and the second query ends with a `WHERE categories.parent_id = all_categories.id`.

You can change how the two are connected by setting the `connect` option, as in `id: :parent_id`, where the left side will be present in the query so it can be connected to the right side on the second query (plus the extra 'IS NULL' default statement for the first query). If the first query already has a condition with the right side of the connection, then the null condition won't be added.

You can also set it to use a `UNION ALL` by calling `cte.union_all!`.

### The depth column

```ruby
cte.with_depth(column_name = 'depth', start: (depth_start_value = 0), as: (expose_name = nil))
```

This option will add a calculated `depth` column to your queries to show on which iteration the row was added. The `as` option allows you to expose the attribute to the main query if you want to grab its results. You don't need to set an alias to use it on `WHERE`, just reference the statement name and the column name, as in `where(all_categories: { depth: 1 })`.

### The path column

```ruby
cte.with_path(column_name = 'path', source: (path_column_source = :primary_key), as: (expose_name = nil))
```

This option will add a calculated `path` column to your queries to show the path followed until reaching the retrieved row (with itself included). It behaves similarly to the `depth` in the matter of the alias. The difference here is that the result will always be an array of strings (varchar). You can use an `ANY` operator to grab any record that contains a given id in the path: `where('? = ANY (all_categories.path)', 3)`.

### Setting up sub_query manually

The `cte.sub_query` option works in the same way as the `cte.query`, which means it supports the same things (Relation, proc, and string). But once it is set, the connection must be defined manually in both definitions (`query` and `sub_query`). Be aware that the automatic setup of the `sub_query` uses a multiple-table FROM clause to make sure records are loaded correctly, as in: `UNION SELECT * FROM categories, all_categories`.

## Detached recursive

Recursive CTE is also available in its detached form through `TorqueRecursiveCTE` and works similarly to its normal form with the addition of the extra settings available only for recursive operations: `sub_query`, `connect`, `union_all`, `with_depth`, and `with_path`.

You can combine the detached form and a plain query to load the recursion result:
```ruby
class CoursesController < ApplicationController
  def index
    all_categories = TorqueRecursiveCTE.create(:all_categories) do |cte|
      cte.query Category.all
      cte.attributes id: :id, title: :title
      cte.with_depth as: :depth
      cte.with_path as: :path
    end

    @categories = Category.all.with(all_categories).from('all_categories')
  end
end
```
