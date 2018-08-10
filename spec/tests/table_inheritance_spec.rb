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
      expect(dump_io.string).to match(/inherits: :activities do \|t\|\n +t\.string/)
    end

    it 'dumps single inheritance without body' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)

      parts = '"activity_blanks"'
      parts << ', id: false'
      parts << ', force: :cascade'
      parts << ', inherits: :activities'
      expect(dump_io.string).to match(/create_table #{parts}(?! do \|t\|)/)
    end

    it 'dumps multiple inheritance' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)

      parts = '"activity_images"'
      parts << ', id: false'
      parts << ', force: :cascade'
      parts << ', inherits: (\[:images, :activities\]|\[:activities, :images\])'
      expect(dump_io.string).to match(/create_table #{parts}/)
    end
  end

  context 'on inheritance' do
    subject { Torque::PostgreSQL::Inheritance }
    let(:scenario) { {
      'M' => %w(N),
      'N' => %w(C),
      'C' => %w(B),
      'B' => %w(A),
      'D' => %w(A),
      'F' => %w(E),
      'G' => %w(E H),
    } }

    before do
      subject.instance_variable_set(:@dependencies, scenario)
      subject.instance_variable_set(:@associations, subject.send(:generate_associations))
    end

    after do
      subject.instance_variable_set(:@sources_loaded, nil)
      subject.instance_variable_set(:@dependencies, nil)
      subject.instance_variable_set(:@associations, nil)
    end

    it 'correctly defines the associations' do
      expect(subject.associations).to eql({
        'A' => %w(B D C N M),
        'B' => %w(C N M),
        'C' => %w(N M),
        'N' => %w(M),
        'E' => %w(F G),
        'H' => %w(G),
      })
    end
  end

  context 'on relation' do
    let(:base) { Activity }
    let(:child) { ActivityBook }

    it 'has its method' do
      expect(base).to respond_to(:only)
    end

    it 'does not mess with original queries' do
      expect(base.all.to_sql).to \
        eql('SELECT "activities".* FROM "activities"')
    end

    it 'adds the only condition to the query' do
      expect(base.only.to_sql).to \
        eql('SELECT "activities".* FROM ONLY "activities"')
    end

    it 'returns the right ammount of entries' do
      base.create(title: 'Activity only')
      child.create(title: 'Activity book')

      expect(base.all.size).to eql(2)
      expect(base.only.size).to eql(1)
      expect(child.all.size).to eql(1)
    end

    it 'correctly identify physical inheritances' do
      expect(Activity.physically_inherited?).to be_falsey
      expect(Comment.physically_inherited?).to be_falsey
      expect(GuestComment.physically_inherited?).to be_falsey

      expect(ActivityBook.physically_inherited?).to be_truthy
      expect(ActivityPost.physically_inherited?).to be_truthy
      expect(ActivityPost::Sample.physically_inherited?).to be_truthy
    end

    it 'correctly generates the tables name' do
      expect(Activity.table_name).to eql('activities')
      expect(Comment.table_name).to eql('comments')
      expect(GuestComment.table_name).to eql('comments')

      expect(ActivityBook.table_name).to eql('activity_books')
      expect(ActivityPost.table_name).to eql('activity_posters')
      expect(ActivityPost::Sample.table_name).to eql('activity_poster_samples')
    end
  end
end
