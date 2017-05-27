require 'spec_helper'

RSpec.describe 'TableInheritance' do
  let(:connection) { ActiveRecord::Base.connection }

  context 'on migration' do
    before :all do
      module ActiveRecord
        module ConnectionAdapters
          module SchemaStatements
            # Mock original create table so we can check SQL
            def create_table(table_name, **options)
              args = []
              args << options.fetch(:temporary, false)
              args << options.fetch(:options, nil)
              args << options.fetch(:as, nil)
              td = create_table_definition(table_name, *args)

              # Does things as the same as schema statements
              if options[:id] != false && !options[:as]
                pk = options.fetch(:primary_key) do
                  ActiveRecord::Base.get_primary_key table_name.to_s.singularize
                end

                if pk.is_a?(Array)
                  td.primary_keys pk
                else
                  td.primary_key pk, options.fetch(:id, :primary_key), options
                end
              end

              yield td if block_given?

              # Now generate the SQL and return it
              schema_creation.accept td
            end
          end
        end
      end
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

    it 'adds the inherits statement for a single inheritance' do
      sql = connection.create_table(:activity_videos, inherits: :activities) do |t|
        t.string :url
      end

      result = 'CREATE TABLE "activity_videos" ('
      result << '"url" character varying'
      result << ')  INHERITS ( "activities" )'
      expect(sql).to eql(result)
    end

    it 'adds the inherits statement for a multiple inheritance' do
      sql = connection.create_table(:activity_tests, inherits: [:activities, :tests]) do |t|
        t.string :grade
      end

      result = 'CREATE TABLE "activity_tests" ('
      result << '"grade" character varying'
      result << ')  INHERITS ( "activities" , "tests" )'
      expect(sql).to eql(result)
    end
  end

  context 'on schema' do
    it 'dumps when has it' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)

      parts = '"activity_videos"'
      parts << ', id: false'
      parts << ', force: :cascade'
      parts << ', options: "INHERITS ( \\"activities\\" )"'
      expect(dump_io.string).to match(/create_table #{parts} do /)
    end
  end
end
