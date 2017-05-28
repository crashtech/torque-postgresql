require 'spec_helper'

RSpec.describe 'TableInheritance' do
  let(:connection) { ActiveRecord::Base.connection }

  context 'on migration' do
    mock_create_table

    it 'does not affect some basic forms of table creation' do
      sql = connection.create_table('schema_migrations', id: false) do |t|
        t.string :version, connection.internal_string_options_for_primary_key
      end

      result = 'CREATE TABLE "schema_migrations" ("version" character varying PRIMARY KEY)'
      expect(sql).to eql(result)
    end

    it 'does not affect simple table creation' do
      sql = connection.create_table(:activities) do |t|
        t.string :title
        t.boolean :active
        t.timestamps
      end

      result = 'CREATE TABLE "activities" ('
      result << '"id" serial primary key'
      result << ', "title" character varying'
      result << ', "active" boolean'
      result << ', "created_at" timestamp NOT NULL'
      result << ', "updated_at" timestamp NOT NULL'
      result << ')'
      expect(sql).to eql(result)
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

      parts = '"activity_videos"'
      parts << ', id: false'
      parts << ', force: :cascade'
      parts << ', inherits: :activities'
      expect(dump_io.string).to match(/create_table #{parts} do /)
      expect(dump_io.string).to match(/inherits: :activities do \|t\|\n +t\.string/)
    end

    it 'dumps single inheritance without body' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)

      parts = '"youtube_videos"'
      parts << ', id: false'
      parts << ', force: :cascade'
      parts << ', inherits: :activity_videos'
      expect(dump_io.string).to match(/create_table #{parts}(?! do \|t\|)/)
    end

    it 'dumps multiple inheritance' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)

      parts = '"activity_images"'
      parts << ', id: false'
      parts << ', force: :cascade'
      parts << ', inherits: \[:activities, :images\]'
      expect(dump_io.string).to match(/create_table #{parts}/)
    end
  end
end
