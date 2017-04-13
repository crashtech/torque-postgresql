require 'spec_helper'

RSpec.describe 'AuxiliaryStatement' do

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

      result = 'WITH "comments" AS (SELECT "comments"."content" AS comment_content,'
      result << ' "comments"."user_id" FROM "comments") SELECT "users".*,'
      result << ' "comments"."comment_content" FROM "users" INNER JOIN "comments"'
      result << ' ON "users"."id" = "comments"."user_id"'
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

    it 'raise an error when traying to use a statement that is not defined' do
      expect{ subject.with(:does_not_exist).to_sql }.to raise_error(ArgumentError)
    end

    it 'raise an error when using an invalid type of join' do
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
      expect(subject.with(:last_comment)).to be_a(ActiveRecord::Relation)
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
