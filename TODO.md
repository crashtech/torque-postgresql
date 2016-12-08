# Main TODO list

Following the PostgreSQL features list on [this page](https://www.postgresql.org/about/featurematrix/).

## Backend

- [ ] Table Inheritance [DOCS](https://www.postgresql.org/docs/9.1/static/ddl-inherit.html)
- [ ] Create view and materialized view [DOCS VIEW](https://www.postgresql.org/docs/9.2/static/sql-createview.html) [DOCS MATERIALIZED VIEW](https://www.postgresql.org/docs/9.3/static/sql-creatematerializedview.html)
- [ ] Ranges and Ranges Index [DOCS](https://www.postgresql.org/docs/9.3/static/rangetypes.html)
- [ ] Constrains and Checks [DOCS](https://www.postgresql.org/docs/9.4/static/ddl-constraints.html)
- [ ] WITHIN GROUP [DOCS](https://www.postgresql.org/docs/9.4/static/sql-expressions.html#SYNTAX-AGGREGATES)
- [ ] WITH ORDINALITY [DOCS](http://www.postgresonline.com/journal/archives/347-LATERAL-WITH-ORDINALITY-numbering-sets.html)

## Performance

- [ ] SKIP LOCKED clause [DOCS](https://www.postgresql.org/docs/9.5/static/sql-select.html#SQL-FOR-UPDATE-SHARE)
- [ ] TABLESAMPLE clause [DOCS](https://www.postgresql.org/docs/9.5/static/sql-select.html#SQL-FROM)

## To check if already exists

- [ ] JSON data type [DOCS](https://www.postgresql.org/docs/9.4/static/datatype-json.html)
- [ ] Explicit Locking [DOCS](https://www.postgresql.org/docs/9.4/static/explicit-locking.html)
- [ ] Update views [DOCS](https://www.postgresql.org/docs/9.5/static/sql-createview.html#SQL-CREATEVIEW-UPDATABLE-VIEWS)
- [ ] Constrains to model error
- [ ] Dictionaries (Fulltext) [DOCS](https://www.postgresql.org/docs/9.4/static/textsearch-dictionaries.html)

## To be evaluated

- [ ] FROM ONLY and FROM asterisk [DOCS](https://www.postgresql.org/docs/9.1/static/ddl-inherit.html)
- [ ] Arel *tableoid* and *pg_class* [DOCS](https://www.postgresql.org/docs/9.1/static/ddl-inherit.html)
- [ ] GROUP BY using GROUPING SETS, CUBE, and ROLLUP [DOCS](https://www.postgresql.org/docs/9.5/static/queries-table-expressions.html#QUERIES-GROUPING-SETS)
- [ ] JSON functions [DOCS](https://www.postgresql.org/docs/9.5/static/functions-json.html)
- [ ] JSON index [DOCS](https://www.postgresql.org/docs/9.4/static/datatype-json.html#JSON-INDEXING)
- [ ] INSERT INTO with *conflict_target* and *conflict_action* [DOCS](https://www.postgresql.org/docs/9.5/static/sql-insert.html)
- [ ] Extra types of joins [DOCS](https://www.postgresql.org/docs/9.4/static/queries-table-expressions.html#QUERIES-JOIN)
- [ ] LATERAL Queries [DOCS](https://www.postgresql.org/docs/9.4/static/queries-table-expressions.html#QUERIES-LATERAL)
- [ ] BRIN Indexes [DOCS](https://www.postgresql.org/docs/9.5/static/brin-intro.html)
- [ ] Aggregate manager [DOCS](https://www.postgresql.org/docs/9.2/static/sql-createaggregate.html)
- [ ] 'Simple' type manager [DOCS](https://www.postgresql.org/docs/9.2/static/sql-createtype.html)

## Desirable

- [ ] Arel windows functions [DOCS](https://www.postgresql.org/docs/9.3/static/functions-window.html)
- [ ] Replace the *postgres_ext* gem
- [ ] Domain manager [DOCS](https://www.postgresql.org/docs/9.2/static/extend-type-system.html#AEN27940)
- [ ] 'Compound' type manager [DOCS](https://www.postgresql.org/docs/9.2/static/sql-createtype.html)
- [x] 'Enum' type manager [DOCS](https://www.postgresql.org/docs/9.2/static/sql-createtype.html)
 - [x] Create, remove and change values
 - [x] Schema dumper
 - [x] Migration up and down
 - [ ] Enum for active model
