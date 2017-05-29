# Main TODO list

Following the PostgreSQL features list on [this page](https://www.postgresql.org/about/featurematrix/).

> **cte** - Common Table Expressions

## v0.1.0

- [x] DOCS!!!
  - [x] Config
  - [x] Auxiliary Statements
  - [x] Interval
  - [x] Enum
  - [x] Distinct On
- [x] CTE queries (auxiliary statements)
  - [x] Configure CTE queries on model, and enable using `with(:name)` on relations
  - [x] Allow custom join type, besides the default InnerJoin
  - [x] Only provides the CTE fields when the main query doesn't select columns
  - [x] Create a exclusive class to hold all the generated auxiliary statements
  - [x] Try to identify join columns
  - [x] Improve performance by saving `@base_table ||= base_table` and `@query_table ||= query_table`
  - [x] Allow access to `table` and `table_name` from the class scope
    - [x] Allow those access on the settings too, *this is important for recursivity*
    - [x] Allow easy access to SQL access and columns on setting
  - [x] Allows `select: {column: :expose}` extra option to `with` command
  - [x] Allows `join: {column: :cte_column}` to do extra filters when using `with` command
  - [x] Allows `cte.polymorphic 'name'` so it can identify both id and type columns
  - [x] Accept Proc as query when configuring the CTE, but asks the source table Class or Name
    - [x] Allows query to be a string too
    - [x] Allows `with` to receive extra parameters and send to the Proc or format the string with `%`
- [x] Interval data type [DOCS](https://www.postgresql.org/docs/9.4/static/datatype-datetime.html#DATATYPE-INTERVAL-INPUT)
  - [x] Setup the interval style to the easier 'iso_8601' [DOCS](https://www.postgresql.org/docs/9.6/static/runtime-config-client.html#RUNTIME-CONFIG-CLIENT-FORMAT)
  - [x] On create table, interval column method
  - [x] Value OID
  - [x] Accepts integer as a value
  - [x] Accepts array and hash as a value
- [x] 'Enum' type manager [DOCS](https://www.postgresql.org/docs/9.2/static/sql-createtype.html)
  - [x] Configurations
  - [x] Allow schema option for database statements
  - [x] Create, remove and change values
  - [x] Schema dumper
  - [x] Migration up and down
  - [x] On create table, enum column method
  - [x] Create single Module or Class for each enum type
  - [x] Enum for active model (based on Enumerize)
    - [x] Generate a method `_text` so the i18n key can have the model name
  - [x] Uses Ruby Comparable module [DOCS](https://ruby-doc.org/core-2.3.0/Comparable.html)
  - [x] Allow methods ended with '?' to check or '!' to replace value
  - [x] I18n support for translating values
  - [x] Uses `chomp!` to check for '?' and '!' methods [DOCS](https://ruby-doc.org/core-2.2.0/String.html#method-i-chomp-21)
  - [x] Allow 'Enum::Roles.each', iteration over class using 'delegate :each, to: :values'
  - [x] Allow manual enum initialization by calling 'enum :roles' on models
- [x] DISTINCT ON [DOCS](https://www.postgresql.org/docs/9.5/static/sql-select.html#SQL-DISTINCT)
  - [x] Static model method
  - [x] Relation method
  - [x] Where-like columns search for querying

## v0.2.0

- [ ] DOCS!!!
  - [ ] Auxiliary Statements
  - [ ] Table Inheritance
  - [ ] Composite
- [ ] CTE queries (auxiliary statements)
  - [x] Allows `requires` setting to create dependecy between CTEs
    - [ ] Create a subclass from ActiveRecord::Relation for internal references
    - [ ] Turn the dependent into a relation so it could be used on the query
  - [ ] Recursive CTE queries
    - [ ] Enables `path`
    - [ ] Enables `depth`
- [x] Table Inheritance [DOCS](https://www.postgresql.org/docs/9.1/static/ddl-inherit.html)
  - [x] `inherits` option while creating a table
  - [x] Allow table creation without columns when having inheritance
  - [x] Keep `inherits` as an option on schema dump
  - [x] FROM ONLY [DOCS](https://www.postgresql.org/docs/9.1/static/ddl-inherit.html)
    - [x] Relation method `only` to affect the from operator
- [ ] 'Composite' type manager [DOCS](https://www.postgresql.org/docs/9.6/static/rowtypes.html)
  - [ ] Configurations
  - [ ] Allow schema option for database statements
  - [ ] Create composite type
  - [ ] Alter composite type
  - [ ] Schema dumper
  - [ ] On create table, composite column method
  - [ ] Read value from database *TEST*
  - [ ] Write value on database *TEST*
  - [ ] Write quotes properly
  - [ ] Create single Module for each composite type *TEST*
  - [ ] Model attribute using as much as possible from ActiveRecord::Base *TEST*
  - [ ] Bind parent instance and attribute where is attatched to internal composite instance (Act as `has_one`) *TEST*
  - [ ] Block querying on Composite types *TEST*
  - [ ] Nested callbacks and validations
  - [ ] Allow composite model class be edited by users by reopening the class
  - [ ] Allow `belongs_to` for composite types *TEST*
    - [ ] Allow eager load
    - [ ] Allow where conditions
  - [ ] Check how it works with `human_attribute_name`
    - [ ] It already works fine using dot syntax `'published.url'` *TEST*

## v0 3.0

- [ ] CTE queries (auxiliary statements)
  - [ ] Tree CTE queries
    - [ ] Provides an `acts_as_tree` method on models to activate this resource
- [ ] Table Inheritance
  - [ ] Create a method `type` that can identify the model that created that entry
  - [ ] Create a method `typed` that gets the entry as the model that created it
- [ ] Enum
  - [ ] Allow generator to postgre cast enum to integer [DOCS](http://stackoverflow.com/a/12347716/7321983)
  - [ ] Accept `pluralize: true` and `singularize: true` to create the enum methods
  - [ ] Enum equivalences
- [ ] Integrate resources with form for
  - [ ] Interval input type
  - [ ] Enum input type
  - [ ] Nested form for composite input type

## Backend

- [ ] Create view and materialized view [DOCS VIEW](https://www.postgresql.org/docs/9.2/static/sql-createview.html) [DOCS MATERIALIZED VIEW](https://www.postgresql.org/docs/9.3/static/sql-creatematerializedview.html)
- [ ] Ranges and Ranges Index [DOCS](https://www.postgresql.org/docs/9.3/static/rangetypes.html)
- [ ] Constrains and Checks [DOCS](https://www.postgresql.org/docs/9.4/static/ddl-constraints.html)
- [ ] WITHIN GROUP [DOCS](https://www.postgresql.org/docs/9.4/static/sql-expressions.html#SYNTAX-AGGREGATES)
- [ ] WITH ORDINALITY [DOCS](http://www.postgresonline.com/journal/archives/347-LATERAL-WITH-ORDINALITY-numbering-sets.html)

## Performance

- [ ] TABLE Command, when using `.all` [DOCS](www.postgresql.org/docs/9.5/static/sql-select.html#SQL-TABLE)
- [ ] SKIP LOCKED clause [DOCS](https://www.postgresql.org/docs/9.5/static/sql-select.html#SQL-FOR-UPDATE-SHARE)
- [ ] TABLESAMPLE clause [DOCS](https://www.postgresql.org/docs/9.5/static/sql-select.html#SQL-FROM)

## To check if already exists

- [ ] Explicit Locking [DOCS](https://www.postgresql.org/docs/9.4/static/explicit-locking.html)
- [ ] Update views [DOCS](https://www.postgresql.org/docs/9.5/static/sql-createview.html#SQL-CREATEVIEW-UPDATABLE-VIEWS)
- [ ] Constrains to model error
- [ ] Dictionaries (Fulltext) [DOCS](https://www.postgresql.org/docs/9.4/static/textsearch-dictionaries.html)

## To be evaluated

- [ ] Arel *tableoid* and *pg_class* [DOCS](https://www.postgresql.org/docs/9.1/static/ddl-inherit.html)
- [ ] GROUP BY using GROUPING SETS, CUBE, and ROLLUP [DOCS](https://www.postgresql.org/docs/9.5/static/queries-table-expressions.html#QUERIES-GROUPING-SETS)
- [ ] JSON functions [DOCS](https://www.postgresql.org/docs/9.5/static/functions-json.html)
- [ ] JSON index [DOCS](https://www.postgresql.org/docs/9.4/static/datatype-json.html#JSON-INDEXING)
- [ ] INSERT INTO with *conflict_target* and *conflict_action* [DOCS](https://www.postgresql.org/docs/9.5/static/sql-insert.html)
- [ ] Extra types of joins [DOCS](https://www.postgresql.org/docs/9.4/static/queries-table-expressions.html#QUERIES-JOIN)
- [ ] LATERAL Queries [DOCS](https://www.postgresql.org/docs/9.4/static/queries-table-expressions.html#QUERIES-LATERAL)
- [ ] BRIN Indexes [DOCS](https://www.postgresql.org/docs/9.5/static/brin-intro.html)
- [ ] 'Simple' type manager [DOCS](https://www.postgresql.org/docs/9.2/static/sql-createtype.html)
- [ ] Allow use the 'stream_each' method from PostgreSQL connection [DOCS](https://deveiate.org/code/pg/PG/Result.html#method-i-stream_each)
  - [ ] Mark all `includes` as `eager_load` so each record brings the information needed
- [ ] FILTER Clause [DOCS](https://www.postgresql.org/docs/9.4/static/sql-expressions.html#SYNTAX-AGGREGATES)
- [ ] GIN Indexes [DOCS](https://www.postgresql.org/docs/current/static/gin-intro.html)
- [ ] Both Enum and Composite builded methods inside a self-generated module

## Desirable

- [ ] Turn queries on 'database_statements' into Arel queries
- [ ] Simple nested relation find (User -> has_many :groups should search for User::Groups, then UserGroups then Groups)
  - [ ] Configuration to enable and disable this feature
- [ ] Replace the 'postgres_ext' gem
  - [ ] Rank windows function
  - [ ] Array operators
- [ ] Domain manager [DOCS](https://www.postgresql.org/docs/9.2/static/extend-type-system.html#AEN27940)
  - [ ] Create domain
  - [ ] Use domain on table creation
  - [ ] Allow domain check
- [ ] `.group`, `.order`, and `.select` Allowing hash association
  - [ ] User the new `resolve_column` on Group
  - [ ] User the new `resolve_column` on Select
  - [ ] User the new `resolve_column` as a base for Order, because it may have :asc or :desc as last value

## Future features

- [ ] CTE queries (auxiliary statements)
  - [ ] Connect relations with auxiliary statements
    - [ ] Allows `with` to accept an hash and identify statements from associations
- [ ] Composite
  - [ ] Accept array of composite (Act as `has_many`)
- [ ] Enum
  - [ ] Accept array of enum and consider it as a set
- [ ] Distinct On
  - [ ] Sanitize test
- [ ] Record column data type (maybe Vector) [DOCS](https://www.postgresql.org/docs/9.6/static/datatype-pseudo.html)
  - [ ] Allow per record extra data customization
  - [ ] Allow using symbol (:string), constant name over ActiveRecord::Type (String), or anything that respond to #cast, #serialize, and #deserialize to map the values
  - [ ] Index on expressions [DOCS](https://www.postgresql.org/docs/current/static/indexes-expressional.html)
  - [ ] Partial index, using `WHERE` [DOCS](https://www.postgresql.org/docs/9.6/static/sql-createindex.html)
  - [ ] Array of record
