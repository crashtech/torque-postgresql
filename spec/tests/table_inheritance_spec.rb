require 'spec_helper'

RSpec.describe 'TableInheritance' do
  let(:connection) { ActiveRecord::Base.connection }

  context 'on migration' do
    mock_create_table

    it 'does not affect some basic forms of table creation' do
      sql = connection.create_table('schema_migrations', id: false) do |t|
        t.string :version, connection.internal_string_options_for_primary_key
      end

      result = 'CREATE TABLE "schema_migrations"'
      result << ' \("version" character varying( NOT NULL)? PRIMARY KEY\)'
      expect(sql).to match(/#{result}/)
    end

    it 'does not affect simple table creation' do
      sql = connection.create_table(:activities) do |t|
        t.string :title
        t.boolean :active
        t.timestamps
      end

      result = 'CREATE TABLE "activities" \('
      result << '"id" (big)?serial primary key'
      result << ', "title" character varying'
      result << ', "active" boolean'
      result << ', "created_at" timestamp NOT NULL'
      result << ', "updated_at" timestamp NOT NULL'
      result << '\)'
      expect(sql).to match(/#{result}/)
    end

    it 'does not affect temporary table creation based on a query' do
      query = 'SELECT * FROM "authors"'
      sql = connection.create_table(:test, temporary: true, as: query)

      result = 'CREATE TEMPORARY TABLE "test"'
      result << " AS #{query}"
      expect(sql).to eql(result)
    end

    it 'adds the inherits statement for a single inheritance' do
      sql = connection.create_table(:activity_videos, inherits: :activities) do |t|
        t.string :url
      end

      result = 'CREATE TABLE "activity_videos" ('
      result << '"url" character varying'
      result << ') INHERITS ( "activities" )'
      expect(sql).to eql(result)
    end

    it 'adds the inherits statement for a multiple inheritance' do
      sql = connection.create_table(:activity_tests, inherits: [:activities, :tests]) do |t|
        t.string :grade
      end

      result = 'CREATE TABLE "activity_tests" ('
      result << '"grade" character varying'
      result << ') INHERITS ( "activities" , "tests" )'
      expect(sql).to eql(result)
    end

    it 'allows empty-body create table operation' do
      sql = connection.create_table(:activity_posts, inherits: :activities)
      result = 'CREATE TABLE "activity_posts" ()'
      result << ' INHERITS ( "activities" )'
      expect(sql).to eql(result)
    end
  end

  context 'on schema' do
    it 'dumps single inheritance with body' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)

      parts = '"activity_books"'
      parts << ', id: false'
      parts << ', force: :cascade'
      parts << ', inherits: :activities'
      expect(dump_io.string).to match(/create_table #{parts} do /)
    end

    it 'dumps single inheritance without body' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)

      parts = '"activity_post_samples"'
      parts << ', id: false'
      parts << ', force: :cascade'
      parts << ', inherits: :activity_posts'
      expect(dump_io.string).to match(/create_table #{parts}(?! do \|t\|)/)
    end

    it 'dumps multiple inheritance' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)

      parts = '"activity_posts"'
      parts << ', id: false'
      parts << ', force: :cascade'
      parts << ', inherits: (\[:images, :activities\]|\[:activities, :images\])'
      expect(dump_io.string).to match(/create_table #{parts}/)
    end
  end

  context 'on schema cache' do
    subject { ActiveRecord::Base.connection.schema_cache }

    it 'correctly defines the associations' do
      scenario = {
        'M' => %w(N),
        'N' => %w(C),
        'C' => %w(B),
        'B' => %w(A),
        'D' => %w(A),
        'F' => %w(E),
        'G' => %w(E H),
      }

      subject.instance_variable_set(:@inheritance_dependencies, scenario)
      subject.instance_variable_set(:@inheritance_associations, subject.send(:generate_associations))
      expect(subject.instance_variable_get(:@inheritance_associations)).to eql({
        'A' => %w(B D C N M),
        'B' => %w(C N M),
        'C' => %w(N M),
        'N' => %w(M),
        'E' => %w(F G),
        'H' => %w(G),
      })

      subject.instance_variable_set(:@inheritance_cache, nil)
      subject.instance_variable_set(:@inheritance_dependencies, nil)
      subject.instance_variable_set(:@inheritance_associations, nil)
    end

    context 'on looking up models' do
      after(:all) do
        schema_cache = ActiveRecord::Base.connection.schema_cache
        schema_cache.instance_variable_set(:@data_sources, {})
        schema_cache.instance_variable_set(:@data_sources_model_names, {})
      end

      it 'respect irregular names' do
        Torque::PostgreSQL.config.irregular_models = {
          'posts' => 'ActivityPost',
        }

        subject.send(:prepare_data_sources)
        list = subject.instance_variable_get(:@data_sources_model_names)
        expect(list).to have_key('posts')
        expect(list['posts']).to eql(ActivityPost)
      end

      it 'does not load irregular where the data source is not defined' do
        Torque::PostgreSQL.config.irregular_models = {
          'products' => 'Product',
        }

        subject.send(:prepare_data_sources)
        list = subject.instance_variable_get(:@data_sources_model_names)
        expect(list).to_not have_key('products')
      end

      {
        'activities' => Activity,
        'activity_posts' => ActivityPost,
        'activity_post_samples' => ActivityPost::Sample,
      }.each do |table_name, expected_model|
        it "translate the table name #{table_name} to #{expected_model.name} model" do
          expect(subject.lookup_model(table_name)).to eql(expected_model)
        end
      end
    end
  end

  context 'on inheritance' do
    let(:base) { Activity }
    let(:child) { ActivityPost }
    let(:child2) { ActivityBook }
    let(:other) { AuthorJournalist }

    it 'has a merged version of attributes' do
      result_base = %w(id author_id title active kind created_at updated_at description url file post_id).to_set
      result_child = %w(id author_id title active kind created_at updated_at file post_id url).to_set
      result_child2 = %w(id author_id title active kind created_at updated_at description url).to_set
      result_other = %w(id name type specialty).to_set

      expect(base.inheritance_merged_attributes).to eql(result_base)
      expect(child.inheritance_merged_attributes).to eql(result_child)
      expect(child2.inheritance_merged_attributes).to eql(result_child2)
      expect(other.inheritance_merged_attributes).to eql(result_other)
    end

    it 'identifies physical inheritance' do
      expect(base.physically_inherited?).to be_falsey
      expect(child.physically_inherited?).to be_truthy
      expect(child2.physically_inherited?).to be_truthy
      expect(other.physically_inherited?).to be_falsey
    end

    it 'returns a list of dependent tables' do
      expect(base.inheritance_dependents).to eql(%w(activity_books activity_posts activity_post_samples))
      expect(child.inheritance_dependents).to eql(%w(activity_post_samples))
      expect(child2.inheritance_dependents).to eql(%w())
      expect(other.inheritance_dependents).to eql(%w())
    end

    it 'can check dependency' do
      expect(base.physically_inheritances?).to be_truthy
      expect(child.physically_inheritances?).to be_truthy
      expect(child2.physically_inheritances?).to be_falsey
      expect(other.physically_inheritances?).to be_falsey
    end

    it 'returns the list of models that the records can be casted to' do
      expect(base.casted_dependents.values.map(&:name)).to eql(%w(ActivityBook ActivityPost ActivityPost::Sample))
      expect(child.casted_dependents.values.map(&:name)).to eql(%w(ActivityPost::Sample))
      expect(child2.casted_dependents.values.map(&:name)).to eql(%w())
      expect(other.casted_dependents.values.map(&:name)).to eql(%w())
    end

    it 'correctly generates the tables name' do
      expect(base.table_name).to eql('activities')
      expect(child.table_name).to eql('activity_posts')
      expect(child2.table_name).to eql('activity_books')
      expect(other.table_name).to eql('authors')
    end
  end

  context 'on relation' do
    let(:base) { Activity }
    let(:child) { ActivityBook }
    let(:other) { AuthorJournalist }

    it 'has operation methods' do
      expect(base).to respond_to(:itself_only)
      expect(base).to respond_to(:cast_records)
      expect(base.new).to respond_to(:cast_record)
    end

    context 'itself only' do
      it 'does not mess with original queries' do
        expect(base.all.to_sql).to \
          eql('SELECT "activities".* FROM "activities"')
      end

      it 'adds the only condition to the query' do
        expect(base.itself_only.to_sql).to \
          eql('SELECT "activities".* FROM ONLY "activities"')
      end

      it 'returns the right ammount of entries' do
        base.create!(title: 'Activity only')
        child.create!(title: 'Activity book')

        expect(base.count).to eql(2)
        expect(base.itself_only.count).to eql(1)
        expect(child.count).to eql(1)
      end
    end

    context 'cast records' do
      before :each do
        base.create(title: 'Activity test')
        child.create(title: 'Activity book', url: 'bookurl1')
        other.create(name: 'An author name')
      end

      it 'does not mess with single table inheritance' do
        result = 'SELECT "authors".* FROM "authors"'
        result << " WHERE \"authors\".\"type\" IN ('AuthorJournalist')"
        expect(other.all.to_sql).to eql(result)
      end

      it 'adds all statements to load all the necessary records' do
        result = 'WITH "record_class" AS (SELECT "pg_class"."oid", "pg_class"."relname" AS _record_class FROM "pg_class")'
        result << ' SELECT "activities".*, "record_class"."_record_class"'
        result << ', "i_0"."description", COALESCE("i_0"."url", "i_1"."url", "i_2"."url") AS url'
        result << ', COALESCE("i_1"."file", "i_2"."file") AS file, COALESCE("i_1"."post_id", "i_2"."post_id") AS post_id'
        result << ", \"record_class\".\"_record_class\" IN ('activity_books', 'activity_posts', 'activity_post_samples') AS _auto_cast"
        result << ' FROM "activities"'
        result << ' INNER JOIN "record_class" ON "activities"."tableoid" = "record_class"."oid"'
        result << ' LEFT OUTER JOIN "activity_books" "i_0" ON "activities"."id" = "i_0"."id"'
        result << ' LEFT OUTER JOIN "activity_posts" "i_1" ON "activities"."id" = "i_1"."id"'
        result << ' LEFT OUTER JOIN "activity_post_samples" "i_2" ON "activities"."id" = "i_2"."id"'
        expect(base.cast_records.all.to_sql).to eql(result)
      end

      it 'can be have simplefied joins' do
        result = 'WITH "record_class" AS (SELECT "pg_class"."oid", "pg_class"."relname" AS _record_class FROM "pg_class")'
        result << ' SELECT "activities".*, "record_class"."_record_class"'
        result << ', "i_0"."description", "i_0"."url"'
        result << ", \"record_class\".\"_record_class\" IN ('activity_books') AS _auto_cast"
        result << ' FROM "activities"'
        result << ' INNER JOIN "record_class" ON "activities"."tableoid" = "record_class"."oid"'
        result << ' LEFT OUTER JOIN "activity_books" "i_0" ON "activities"."id" = "i_0"."id"'
        expect(base.cast_records(child).all.to_sql).to eql(result)
      end

      it 'can be filtered by record type' do
        result = 'WITH "record_class" AS (SELECT "pg_class"."oid", "pg_class"."relname" AS _record_class FROM "pg_class")'
        result << ' SELECT "activities".*, "record_class"."_record_class"'
        result << ', "i_0"."description", "i_0"."url"'
        result << ", \"record_class\".\"_record_class\" IN ('activity_books') AS _auto_cast"
        result << ' FROM "activities"'
        result << ' INNER JOIN "record_class" ON "activities"."tableoid" = "record_class"."oid"'
        result << ' LEFT OUTER JOIN "activity_books" "i_0" ON "activities"."id" = "i_0"."id"'
        result << " WHERE \"record_class\".\"_record_class\" = 'activity_books'"
        expect(base.cast_records(child, filter: true).all.to_sql).to eql(result)
      end

      it 'works with count and does not add extra columns' do
        result = 'WITH "record_class" AS (SELECT "pg_class"."oid", "pg_class"."relname" AS _record_class FROM "pg_class")'
        result << ' SELECT COUNT(*)'
        result << ' FROM "activities"'
        result << ' INNER JOIN "record_class" ON "activities"."tableoid" = "record_class"."oid"'
        result << ' LEFT OUTER JOIN "activity_books" "i_0" ON "activities"."id" = "i_0"."id"'
        result << ' LEFT OUTER JOIN "activity_posts" "i_1" ON "activities"."id" = "i_1"."id"'
        result << ' LEFT OUTER JOIN "activity_post_samples" "i_2" ON "activities"."id" = "i_2"."id"'
        query = get_last_executed_query{ base.cast_records.all.count }
        expect(query).to eql(result)
      end

      it 'works with sum and does not add extra columns' do
        result = 'WITH "record_class" AS (SELECT "pg_class"."oid", "pg_class"."relname" AS _record_class FROM "pg_class")'
        result << ' SELECT SUM("activities"."id")'
        result << ' FROM "activities"'
        result << ' INNER JOIN "record_class" ON "activities"."tableoid" = "record_class"."oid"'
        result << ' LEFT OUTER JOIN "activity_books" "i_0" ON "activities"."id" = "i_0"."id"'
        result << ' LEFT OUTER JOIN "activity_posts" "i_1" ON "activities"."id" = "i_1"."id"'
        result << ' LEFT OUTER JOIN "activity_post_samples" "i_2" ON "activities"."id" = "i_2"."id"'
        query = get_last_executed_query{ base.cast_records.all.sum(:id) }
        expect(query).to eql(result)
      end

      it 'returns the correct model object' do
        ActivityPost.create(title: 'Activity post')
        ActivityPost::Sample.create(title: 'Activity post')
        records = base.cast_records.order(:id).load.to_a

        expect(records[0].class).to eql(Activity)
        expect(records[1].class).to eql(ActivityBook)
        expect(records[2].class).to eql(ActivityPost)
        expect(records[3].class).to eql(ActivityPost::Sample)
      end

      it 'does not cast unnecessary records' do
        ActivityPost.create(title: 'Activity post')
        records = base.cast_records(ActivityBook).order(:id).load.to_a

        expect(records[0].class).to eql(Activity)
        expect(records[1].class).to eql(ActivityBook)
        expect(records[2].class).to eql(Activity)
      end

      it 'correctly identify same name attributes' do
        ActivityPost.create(title: 'Activity post', url: 'posturl1')
        records = base.cast_records.order(:id).load.to_a

        expect(records[1].url).to eql('bookurl1')
        expect(records[2].url).to eql('posturl1')
      end
    end

    context 'cast record' do
      before :each do
        base.create(title: 'Activity test')
        child.create(title: 'Activity book')
        other.create(name: 'An author name')
      end

      it 'does not affect normal records' do
        base.instance_variable_set(:@casted_dependents, {})
        expect(base.first.cast_record).to be_a(base)
        expect(child.first.cast_record).to be_a(child)
        expect(other.first.cast_record).to be_a(other)
      end

      it 'rises an error when the casted model cannot be defined' do
        base.instance_variable_set(:@casted_dependents, {})
        expect{ base.second.cast_record }.to raise_error(ArgumentError, /to type 'activity_books'/)
      end

      it 'can return the record class even when the auxiliary statement is not mentioned' do
        expect(base.first._record_class).to eql('activities')
        expect(base.second._record_class).to eql('activity_books')
        expect(other.first._record_class).to eql('authors')
      end

      it 'does trigger record casting when accessed through inheritance' do
        base.instance_variable_set(:@casted_dependents, nil)
        expect(base.second.cast_record).to eql(child.first)
      end
    end
  end
end
