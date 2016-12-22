# Main TODO list

Following the PostgreSQL features list on [this page](https://www.postgresql.org/about/featurematrix/).

## Backend

- [ ] Table Inheritance [DOCS](https://www.postgresql.org/docs/9.1/static/ddl-inherit.html)
 - [ ] FROM ONLY and FROM asterisk [DOCS](https://www.postgresql.org/docs/9.1/static/ddl-inherit.html)
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
- [ ] FILTER Clause [DOCS](https://www.postgresql.org/docs/9.4/static/sql-expressions.html#SYNTAX-AGGREGATES)
- [ ] GIN Indexes [DOCS](https://www.postgresql.org/docs/current/static/gin-intro.html)

## Desirable

- [ ] Record column data type (maybe Vector) [DOCS](https://www.postgresql.org/docs/9.6/static/datatype-pseudo.html)
 - [ ] Allow per record extra data customization
 - [ ] Index on expressions [DOCS](https://www.postgresql.org/docs/current/static/indexes-expressional.html)
 - [ ] Partial index, using `WHERE` [DOCS](https://www.postgresql.org/docs/9.6/static/sql-createindex.html)
- [x] Interval data type [DOCS](https://www.postgresql.org/docs/9.4/static/datatype-datetime.html#DATATYPE-INTERVAL-INPUT)
 - [x] Setup the interval style to the easier 'iso_8601' [DOCS](https://www.postgresql.org/docs/9.6/static/runtime-config-client.html#RUNTIME-CONFIG-CLIENT-FORMAT)
 - [x] On create table, interval column method
 - [x] Value OID
 - [x] Accepts integer as a value
 - [x] Accepts array and hash as a value
- [ ] Simple nested relation find (User -> has_many :groups should search for UserGroups then Groups)
 - [ ] Configuration to enable and disable this feature
- [ ] Arel windows functions [DOCS](https://www.postgresql.org/docs/9.3/static/functions-window.html)
 - [ ] Allow partition over
- [ ] Replace the 'postgres_ext' gem
 - [ ] Basic CTE queries
 - [ ] Recursive CTE queries
 - [ ] Rank windows function
 - [ ] Array operators
- [ ] Domain manager [DOCS](https://www.postgresql.org/docs/9.2/static/extend-type-system.html#AEN27940)
 - [ ] Create domain
 - [ ] Use domain on table creation
 - [ ] Allow domain check
- [ ] 'Composite' type manager [DOCS](https://www.postgresql.org/docs/9.6/static/rowtypes.html)
 - [x] Configurations
 - [ ] Allow schema option for database statements
 - [x] Create composite type
 - [ ] Alter composite type
 - [x] Schema dumper
 - [x] On create table, composite column method
 - [x] Read value from database *TEST*
 - [x] Write value on database *TEST*
 - [x] Write quotes properly
 - [x] Create single Module for each composite type *TEST*
 - [x] Model attribute using as much as possible from ActiveRecord::Base *TEST*
 - [x] Bind parent instance and attribute where is attatched to internal composite instance (Act as `has_one`) *TEST*
 - [x] Block querying on Composite types *TEST*
 - [ ] Nested callbacks and validations
 - [ ] Accept array of composite (Act as `has_many`)
 - [ ] Allow composite model class be edited by users by reopening the class
 - [ ] Allow `belongs_to` for composite types
- [ ] 'Enum' type manager [DOCS](https://www.postgresql.org/docs/9.2/static/sql-createtype.html)
 - [x] Configurations
 - [x] Allow schema option for database statements
 - [x] Create, remove and change values
 - [x] Schema dumper
 - [x] Migration up and down
 - [x] On create table, enum column method
 - [x] Create single Module or Class for each enum type *TEST*
 - [ ] Enum for active model (based on Enumerize and StringInquirer)
 - [x] Uses Ruby Comparable module [DOCS](https://ruby-doc.org/core-2.3.0/Comparable.html) *TEST*
 - [ ] Accept array of enum and consider it as a set
 - [ ] I18n support for translating values
- [x] DISTINCT ON [DOCS](https://www.postgresql.org/docs/9.5/static/sql-select.html#SQL-DISTINCT)
 - [x] Static model method
 - [x] Relation method
 - [x] Where-like columns search for querying
 - [ ] Sanatize tests
- [ ] `.group`, `.order`, and `.select` Allowing hash association
 - [ ] User the new `resolve_column` on Group
 - [ ] User the new `resolve_column` on Select
 - [ ] User the new `resolve_column` as a base for Order, because it may have :asc or :desc as last value

## Form for

- [ ] Integrate resources with form for
