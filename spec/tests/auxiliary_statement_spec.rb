require 'spec_helper'

RSpec.describe 'AuxiliaryStatement' do
  before :each do
    User.auxiliary_statements_list = {}
  end

  context 'on relation' do
    let(:klass) { User }
    subject { klass.unscoped }

    it 'has its method' do
      expect(subject).to respond_to(:with)
    end

    it 'can perform simple queries' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes content: :comment_content
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT "comments"."content" AS comment_content, "comments"."user_id" FROM "comments")'
      result << ' SELECT "users".*, "comments"."comment_content" FROM "users"'
      result << ' INNER JOIN "comments" ON "users"."id" = "comments"."user_id"'
      expect(subject.with(:comments).to_sql).to eql(result)
    end

    it 'can perform more complex queries' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.distinct_on(:user_id).order(:user_id, id: :desc)
        cte.attributes content: :last_comment
      end

      result = 'WITH "comments" AS (SELECT DISTINCT ON ( "comments"."user_id" )'
      result << ' "comments"."content" AS last_comment, "comments"."user_id"'
      result << ' FROM "comments" ORDER BY "comments"."user_id" ASC,'
      result << ' "comments"."id" DESC) SELECT "users".*,'
      result << ' "comments"."last_comment" FROM "users" INNER JOIN "comments"'
      result << ' ON "users"."id" = "comments"."user_id"'
      expect(subject.with(:comments).to_sql).to eql(result)
    end

    it 'accepts extra select columns' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes content: :comment_content
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT "comments"."content" AS comment_content, "comments"."user_id", "comments"."slug" AS comment_slug FROM "comments")'
      result << ' SELECT "users".*, "comments"."comment_content", "comments"."comment_slug" FROM "users"'
      result << ' INNER JOIN "comments" ON "users"."id" = "comments"."user_id"'
      expect(subject.with(:comments, select: {slug: :comment_slug}).to_sql).to eql(result)
    end

    it 'accepts extra join columns' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes content: :comment_content
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT "comments"."content" AS comment_content, "comments"."user_id", "comments"."active" FROM "comments")'
      result << ' SELECT "users".*, "comments"."comment_content" FROM "users"'
      result << ' INNER JOIN "comments" ON "users"."id" = "comments"."user_id" AND "comments"."active" = \'t\''
      expect(subject.with(:comments, join: {active: true}).to_sql).to eql(result)
    end

    it 'accepts string as attributes' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes sql('MAX(id)') => :comment_id
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT MAX(id) AS comment_id, "comments"."user_id" FROM "comments")'
      result << ' SELECT "users".*, "comments"."comment_id" FROM "users"'
      result << ' INNER JOIN "comments" ON "users"."id" = "comments"."user_id"'
      expect(subject.with(:comments).to_sql).to eql(result)
    end

    it 'accepts arel attribute as attributes' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes col(:id).minimum => :comment_id
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT MIN("comments"."id") AS comment_id, "comments"."user_id" FROM "comments")'
      result << ' SELECT "users".*, "comments"."comment_id" FROM "users"'
      result << ' INNER JOIN "comments" ON "users"."id" = "comments"."user_id"'
      expect(subject.with(:comments).to_sql).to eql(result)
    end

    it 'accepts custom join properties' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes content: :comment_content
        cte.join name: :id, 'a.col' => :col
      end

      result = 'WITH "comments" AS (SELECT "comments"."content" AS comment_content,'
      result << ' "comments"."id", "comments"."col" FROM "comments") SELECT "users".*,'
      result << ' "comments"."comment_content" FROM "users" INNER JOIN "comments"'
      result << ' ON "users"."name" = "comments"."id" AND "a"."col" = "comments"."col"'
      expect(subject.with(:comments).to_sql).to eql(result)
    end

    it 'can perform other types of joins' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes content: :comment_content
        cte.join_type :left
      end

      result = 'WITH "comments" AS (SELECT "comments"."content" AS comment_content,'
      result << ' "comments"."user_id" FROM "comments") SELECT "users".*,'
      result << ' "comments"."comment_content" FROM "users" LEFT OUTER JOIN "comments"'
      result << ' ON "users"."id" = "comments"."user_id"'
      expect(subject.with(:comments).to_sql).to eql(result)
    end

    context 'with dependency' do
      before :each do
        klass.send(:auxiliary_statement, :comments1) do |cte|
          cte.query Comment.all
          cte.attributes content: :comment_content1
        end

        klass.send(:auxiliary_statement, :comments2) do |cte|
          cte.requires :comments1
          cte.query Comment.all
          cte.attributes content: :comment_content2
        end
      end

      it 'can requires another statement as dependency' do
        result = 'WITH '
        result << '"comments1" AS (SELECT "comments"."content" AS comment_content1, "comments"."user_id" FROM "comments"), '
        result << '"comments2" AS (SELECT "comments"."content" AS comment_content2, "comments"."user_id" FROM "comments")'
        result << ' SELECT "users".*, "comments2"."comment_content2" FROM "users"'
        result << ' INNER JOIN "comments1" ON "users"."id" = "comments1"."user_id"'
        result << ' INNER JOIN "comments2" ON "users"."id" = "comments2"."user_id"'
        expect(subject.with(:comments2).to_sql).to eql(result)
      end

      it 'can uses already already set dependent' do
        result = 'WITH '
        result << '"comments1" AS (SELECT "comments"."content" AS comment_content1, "comments"."user_id" FROM "comments"), '
        result << '"comments2" AS (SELECT "comments"."content" AS comment_content2, "comments"."user_id" FROM "comments")'
        result << ' SELECT "users".*, "comments1"."comment_content1", "comments2"."comment_content2" FROM "users"'
        result << ' INNER JOIN "comments1" ON "users"."id" = "comments1"."user_id"'
        result << ' INNER JOIN "comments2" ON "users"."id" = "comments2"."user_id"'
        expect(subject.with(:comments1, :comments2).to_sql).to eql(result)
      end

      it 'raises an error if the dependent does not exist' do
        klass.send(:auxiliary_statement, :comments2) do |cte|
          cte.requires :comments3
          cte.query Comment.all
          cte.attributes content: :comment_content2
        end
        expect{ subject.with(:comments2).to_sql }.to raise_error(ArgumentError)
      end
    end

    context 'query as string' do
      it 'performs correctly' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, 'SELECT * FROM comments'
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        result = 'WITH "comments" AS (SELECT * FROM comments)'
        result << ' SELECT "users".*, "comments"."comment" FROM "users"'
        result << ' INNER JOIN "comments" ON "users"."id" = "comments"."user_id"'
        expect(subject.with(:comments).to_sql).to eql(result)
      end

      it 'accepts arguments to format the query' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, 'SELECT * FROM comments WHERE active = %s'
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        result = 'WITH "comments" AS (SELECT * FROM comments WHERE active = \'t\')'
        result << ' SELECT "users".*, "comments"."comment" FROM "users"'
        result << ' INNER JOIN "comments" ON "users"."id" = "comments"."user_id"'
        expect(subject.with(:comments, uses: [true]).to_sql).to eql(result)
      end

      it 'raises an error when join columns are not given' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, 'SELECT * FROM comments'
          cte.attributes content: :comment
        end

        expect{ subject.with(:comments).to_sql }.to raise_error(ArgumentError, /join columns/)
      end

      it 'raises an error when not given the table name as first argument' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query 'SELECT * FROM comments'
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        expect{ subject.with(:comments).to_sql }.to raise_error(ArgumentError, /table name/)
      end
    end

    context 'query as proc' do
      it 'performs correctly for result as relation' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, -> { Comment.all }
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        result = 'WITH "comments" AS'
        result << ' (SELECT "comments"."content" AS comment, "comments"."user_id" FROM "comments")'
        result << ' SELECT "users".*, "comments"."comment" FROM "users"'
        result << ' INNER JOIN "comments" ON "users"."id" = "comments"."user_id"'
        expect(subject.with(:comments).to_sql).to eql(result)
      end

      it 'performs correctly for anything that has a call method' do
        obj = Struct.new(:call).new('SELECT * FROM comments')
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, obj
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        result = 'WITH "comments" AS (SELECT * FROM comments)'
        result << ' SELECT "users".*, "comments"."comment" FROM "users"'
        result << ' INNER JOIN "comments" ON "users"."id" = "comments"."user_id"'
        expect(subject.with(:comments).to_sql).to eql(result)
      end

      it 'performs correctly for result as string' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, -> { 'SELECT * FROM comments' }
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        result = 'WITH "comments" AS (SELECT * FROM comments)'
        result << ' SELECT "users".*, "comments"."comment" FROM "users"'
        result << ' INNER JOIN "comments" ON "users"."id" = "comments"."user_id"'
        expect(subject.with(:comments).to_sql).to eql(result)
      end

      it 'performs correctly when the proc requires arguments' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, -> (status) { Comment.where(active: status) }
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        result = 'WITH "comments" AS'
        result << ' (SELECT "comments"."content" AS comment, "comments"."user_id" FROM "comments" WHERE "comments"."active" = $1)'
        result << ' SELECT "users".*, "comments"."comment" FROM "users"'
        result << ' INNER JOIN "comments" ON "users"."id" = "comments"."user_id"'
        expect(subject.with(:comments, uses: [true]).to_sql).to eql(result)
      end

      it 'raises an error when join columns are not given' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, -> { Comment.all }
          cte.attributes content: :comment
        end

        expect{ subject.with(:comments).to_sql }.to raise_error(ArgumentError, /join columns/)
      end

      it 'raises an error when not given the table name as first argument' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query -> { Comment.all }
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        expect{ subject.with(:comments).to_sql }.to raise_error(ArgumentError, /table name/)
      end

      it 'raises an error when the result of the proc is an invalid type' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, -> { false }
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        expect{ subject.with(:comments).to_sql }.to raise_error(ArgumentError, /query objects/)
      end
    end

    it 'can uses join on polymorphic relations' do
      Comment.columns_hash['source_id'] = true
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes content: :comment
        cte.polymorphic :source
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT "comments"."content" AS comment, "comments"."source_id",'
      result << ' "comments"."source_type" FROM "comments")'
      result << ' SELECT "users".*, "comments"."comment" FROM "users"'
      result << ' INNER JOIN "comments" ON "users"."id" = "comments"."source_id"'
      result << ' AND "comments"."source_type" = \'User\''
      expect(subject.with(:comments).to_sql).to eql(result)
      Comment.columns_hash.delete('source_id')
    end

    it 'raises an error when using an invalid type of object as query' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query :string, String
      end

      expect{ subject.with(:comments).to_sql }.to raise_error(ArgumentError, /object types/)
    end

    it 'raises an error when traying to use a statement that is not defined' do
      expect{ subject.with(:does_not_exist).to_sql }.to raise_error(ArgumentError)
    end

    it 'raises an error when using an invalid type of join' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes content: :comment_content
        cte.join_type :invalid
      end

      expect{ subject.with(:comments).to_sql }.to raise_error(ArgumentError)
    end
  end

  context 'on model' do
    subject { User }

    it 'has its configurator' do
      expect(subject.protected_methods).to include(:cte)
      expect(subject.protected_methods).to include(:auxiliary_statement)
    end

    it 'allows configurate new auxiliary statements' do
      subject.send(:auxiliary_statement, :cte1)
      expect(subject.auxiliary_statements_list).to include(:cte1)
      expect(subject.const_defined?('Cte1_AuxiliaryStatement')).to be_truthy
    end

    it 'has its query method' do
      expect(subject).to respond_to(:with)
    end

    it 'returns a relation when using the method' do
      subject.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes content: :comment_content
      end
      expect(subject.with(:comments)).to be_a(ActiveRecord::Relation)
    end
  end

  context 'on settings' do
    let(:statement_klass) do
      User.send(:auxiliary_statement, :statement)
      User::Statement_AuxiliaryStatement
    end

    subject { Torque::PostgreSQL::AuxiliaryStatement::Settings.new(statement_klass) }

    it 'has access to base' do
      expect(subject.base).to eql(User)
      expect(subject.base_table).to be_a(Arel::Table)
    end

    it 'has access to statement table' do
      expect(subject.table_name).to eql('statement')
      expect(subject.table).to be_a(Arel::Table)
    end

    it 'has access to the query arel table' do
      subject.query Comment.all
      expect(subject.query_table).to be_a(Arel::Table)
    end

    it 'raises an error when trying to access query table before defining the query' do
      expect{ subject.with(:comments).to_sql }.to raise_error(StandardError)
    end
  end

end
