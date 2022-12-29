require 'spec_helper'

RSpec.describe 'AuxiliaryStatement' do
  before :each do
    User.auxiliary_statements_list = {}
  end

  context 'on relation' do
    let(:klass) { User }
    let(:true_value) { 'TRUE' }
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
      result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'
      expect(subject.with(:comments).arel.to_sql).to eql(result)
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
      result << ' ON "comments"."user_id" = "users"."id"'
      expect(subject.with(:comments).arel.to_sql).to eql(result)
    end

    it 'accepts extra select columns' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes content: :comment_content
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT "comments"."content" AS comment_content, "comments"."slug" AS comment_slug, "comments"."user_id" FROM "comments")'
      result << ' SELECT "users".*, "comments"."comment_content", "comments"."comment_slug" FROM "users"'
      result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'
      expect(subject.with(:comments, select: {slug: :comment_slug}).arel.to_sql).to eql(result)
    end

    it 'accepts extra join columns' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes content: :comment_content
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT "comments"."content" AS comment_content, "comments"."user_id", "comments"."active" FROM "comments")'
      result << ' SELECT "users".*, "comments"."comment_content" FROM "users"'
      result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id" AND "comments"."active" = "users"."active"'
      expect(subject.with(:comments, join: {active: :active}).arel.to_sql).to eql(result)
    end

    it 'accepts extra conditions' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes content: :comment_content
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT "comments"."content" AS comment_content, "comments"."user_id"'
      result << ' FROM "comments" WHERE "comments"."active" = $1)'
      result << ' SELECT "users".*, "comments"."comment_content" FROM "users"'
      result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'
      expect(subject.with(:comments, where: {active: true}).arel.to_sql).to eql(result)
    end

    it 'accepts scopes from both sides' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.where(id: 1).all
        cte.attributes content: :comment_content
      end

      query = subject.where(id: 2).with(:comments)

      result = 'WITH "comments" AS'
      result << ' (SELECT "comments"."content" AS comment_content, "comments"."user_id" FROM "comments"'
      result << ' WHERE "comments"."id" = $1)'
      result << ' SELECT "users".*, "comments"."comment_content" FROM "users"'
      result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'
      result << ' WHERE "users"."id" = $2'

      expect(query.arel.to_sql).to eql(result)
      expect(query.send(:bound_attributes).map(&:value_before_type_cast)).to eql([1, 2])
    end

    it 'accepts string as attributes' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes sql('MAX(id)') => :comment_id
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT MAX(id) AS comment_id, "comments"."user_id" FROM "comments")'
      result << ' SELECT "users".*, "comments"."comment_id" FROM "users"'
      result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'
      expect(subject.with(:comments).arel.to_sql).to eql(result)
    end

    it 'accepts complex string as attributes' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes sql('ROW_NUMBER() OVER (PARTITION BY ORDER BY "comments"."id")') => :comment_id
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT ROW_NUMBER() OVER (PARTITION BY ORDER BY "comments"."id") AS comment_id, "comments"."user_id" FROM "comments")'
      result << ' SELECT "users".*, "comments"."comment_id" FROM "users"'
      result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'
      expect(subject.with(:comments).arel.to_sql).to eql(result)
    end

    it 'accepts arel attribute as attributes' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes col(:id).minimum => :comment_id
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT MIN("comments"."id") AS comment_id, "comments"."user_id" FROM "comments")'
      result << ' SELECT "users".*, "comments"."comment_id" FROM "users"'
      result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'
      expect(subject.with(:comments).arel.to_sql).to eql(result)
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
      result << ' ON "comments"."id" = "users"."name" AND "comments"."col" = "a"."col"'
      expect(subject.with(:comments).arel.to_sql).to eql(result)
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
      result << ' ON "comments"."user_id" = "users"."id"'
      expect(subject.with(:comments).arel.to_sql).to eql(result)
    end

    it 'can manually define the association' do
      klass.has_many :sample_comment, class_name: 'Comment', foreign_key: :a_user_id
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.through :sample_comment
        cte.attributes content: :sample_content
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT "comments"."content" AS sample_content, "comments"."a_user_id" FROM "comments")'
      result << ' SELECT "users".*, "comments"."sample_content" FROM "users"'
      result << ' INNER JOIN "comments" ON "comments"."a_user_id" = "users"."id"'
      expect(subject.with(:comments).arel.to_sql).to eql(result)
    end

    it 'accepts complex scopes from dependencies' do
      klass.send(:auxiliary_statement, :comments1) do |cte|
        cte.query Comment.where(id: 1).all
        cte.attributes content: :comment_content1
      end

      klass.send(:auxiliary_statement, :comments2) do |cte|
        cte.requires :comments1
        cte.query Comment.where(id: 2).all
        cte.attributes content: :comment_content2
      end

      query = subject.where(id: 3).with(:comments2)

      result = 'WITH '
      result << '"comments1" AS (SELECT "comments"."content" AS comment_content1, "comments"."user_id" FROM "comments" WHERE "comments"."id" = $1), '
      result << '"comments2" AS (SELECT "comments"."content" AS comment_content2, "comments"."user_id" FROM "comments" WHERE "comments"."id" = $2)'
      result << ' SELECT "users".*, "comments1"."comment_content1", "comments2"."comment_content2" FROM "users"'
      result << ' INNER JOIN "comments1" ON "comments1"."user_id" = "users"."id"'
      result << ' INNER JOIN "comments2" ON "comments2"."user_id" = "users"."id"'
      result << ' WHERE "users"."id" = $3'

      expect(query.arel.to_sql).to eql(result)
      expect(query.send(:bound_attributes).map(&:value_before_type_cast)).to eql([1, 2, 3])
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
        result << ' SELECT "users".*, "comments1"."comment_content1", "comments2"."comment_content2" FROM "users"'
        result << ' INNER JOIN "comments1" ON "comments1"."user_id" = "users"."id"'
        result << ' INNER JOIN "comments2" ON "comments2"."user_id" = "users"."id"'
        expect(subject.with(:comments2).arel.to_sql).to eql(result)
      end

      it 'can uses already already set dependent' do
        result = 'WITH '
        result << '"comments1" AS (SELECT "comments"."content" AS comment_content1, "comments"."user_id" FROM "comments"), '
        result << '"comments2" AS (SELECT "comments"."content" AS comment_content2, "comments"."user_id" FROM "comments")'
        result << ' SELECT "users".*, "comments1"."comment_content1", "comments2"."comment_content2" FROM "users"'
        result << ' INNER JOIN "comments1" ON "comments1"."user_id" = "users"."id"'
        result << ' INNER JOIN "comments2" ON "comments2"."user_id" = "users"."id"'
        expect(subject.with(:comments1, :comments2).arel.to_sql).to eql(result)
      end

      it 'raises an error if the dependent does not exist' do
        klass.send(:auxiliary_statement, :comments2) do |cte|
          cte.requires :comments3
          cte.query Comment.all
          cte.attributes content: :comment_content2
        end
        expect{ subject.with(:comments2).arel.to_sql }.to raise_error(ArgumentError)
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
        result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'
        expect(subject.with(:comments).arel.to_sql).to eql(result)
      end

      it 'accepts arguments to format the query' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, 'SELECT * FROM comments WHERE active = %{active}'
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        result = "WITH \"comments\" AS (SELECT * FROM comments WHERE active = #{true_value})"
        result << ' SELECT "users".*, "comments"."comment" FROM "users"'
        result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'
        expect(subject.with(:comments, args: {active: true}).arel.to_sql).to eql(result)
      end

      it 'raises an error when join columns are not given' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, 'SELECT * FROM comments'
          cte.attributes content: :comment
        end

        expect{ subject.with(:comments).arel.to_sql }.to raise_error(ArgumentError, /join columns/)
      end

      it 'not raises an error when not given the table name as first argument' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query 'SELECT * FROM comments'
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        expect{ subject.with(:comments).arel.to_sql }.not_to raise_error
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
        result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'
        expect(subject.with(:comments).arel.to_sql).to eql(result)
      end

      it 'performs correctly for anything that has a call method' do
        obj = Struct.new(:call, :arity).new('SELECT * FROM comments', 0)
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, obj
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        result = 'WITH "comments" AS (SELECT * FROM comments)'
        result << ' SELECT "users".*, "comments"."comment" FROM "users"'
        result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'
        expect(subject.with(:comments).arel.to_sql).to eql(result)
      end

      it 'performs correctly for result as string' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, -> { 'SELECT * FROM comments' }
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        result = 'WITH "comments" AS (SELECT * FROM comments)'
        result << ' SELECT "users".*, "comments"."comment" FROM "users"'
        result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'
        expect(subject.with(:comments).arel.to_sql).to eql(result)
      end

      it 'performs correctly when the proc requires arguments' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, -> (args) { Comment.where(id: args.id) }
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        query = subject.with(:comments, args: {id: 1})

        result = 'WITH "comments" AS'
        result << ' (SELECT "comments"."content" AS comment, "comments"."user_id"'
        result << ' FROM "comments" WHERE "comments"."id" = $1)'
        result << ' SELECT "users".*, "comments"."comment" FROM "users"'
        result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'

        expect(query.arel.to_sql).to eql(result)
        expect(query.send(:bound_attributes).map(&:value_before_type_cast)).to eql([1])
      end

      it 'raises an error when join columns are not given' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, -> { Author.all }
          cte.attributes content: :comment
        end

        expect{ subject.with(:comments).arel.to_sql }.to raise_error(ArgumentError, /join columns/)
      end

      it 'not raises an error when not given the table name as first argument' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query -> { Comment.all }
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        expect{ subject.with(:comments).arel.to_sql }.not_to raise_error
      end

      it 'raises an error when the result of the proc is an invalid type' do
        klass.send(:auxiliary_statement, :comments) do |cte|
          cte.query :comments, -> { false }
          cte.attributes content: :comment
          cte.join id: :user_id
        end

        expect{ subject.with(:comments).arel.to_sql }.to raise_error(ArgumentError, /query objects/)
      end
    end

    context 'with inheritance' do
      let(:base) { Activity }
      let(:klass) { ActivityBook }

      it 'accepts ancestors auxiliary statements' do
        base.send(:auxiliary_statement, :authors) do |cte|
          cte.query Author.all
          cte.attributes name: :author_name
          cte.join author_id: :id
        end

        result = 'WITH "authors" AS'
        result << ' (SELECT "authors"."name" AS author_name, "authors"."id" FROM "authors")'
        result << ' SELECT "activity_books".*, "authors"."author_name" FROM "activity_books"'
        result << ' INNER JOIN "authors" ON "authors"."id" = "activity_books"."author_id"'
        expect(subject.with(:authors).arel.to_sql).to eql(result)
      end

      it 'can replace ancestors auxiliary statements' do
        base.send(:auxiliary_statement, :authors) do |cte|
          cte.query Author.all
          cte.attributes name: :author_name
          cte.join author_id: :id
        end

        klass.send(:auxiliary_statement, :authors) do |cte|
          cte.query Author.all
          cte.attributes type: :author_type
          cte.join author_id: :id
        end

        result = 'WITH "authors" AS'
        result << ' (SELECT "authors"."type" AS author_type, "authors"."id" FROM "authors")'
        result << ' SELECT "activity_books".*, "authors"."author_type" FROM "activity_books"'
        result << ' INNER JOIN "authors" ON "authors"."id" = "activity_books"."author_id"'
        expect(subject.with(:authors).arel.to_sql).to eql(result)
      end

      it 'raises an error when no class has the auxiliary statement' do
        expect{ subject.with(:comments).arel.to_sql }.to raise_error(ArgumentError)
      end
    end

    context 'recursive' do
      let(:klass) { Course }

      it 'correctly build a recursive cte' do
        klass.send(:recursive_auxiliary_statement, :all_categories) do |cte|
          cte.query Category.all
          cte.join id: :parent_id
        end

        result = 'WITH RECURSIVE "all_categories" AS ('
        result << ' SELECT "categories"."id", "categories"."parent_id"'
        result << ' FROM "categories"'
        result << ' WHERE "categories"."parent_id" IS NULL'
        result << ' UNION'
        result << ' SELECT "categories"."id", "categories"."parent_id"'
        result << ' FROM "categories", "all_categories"'
        result << ' WHERE "categories"."parent_id" = "all_categories"."id"'
        result << ' ) SELECT "courses".* FROM "courses" INNER JOIN "all_categories"'
        result << ' ON "all_categories"."parent_id" = "courses"."id"'
        expect(subject.with(:all_categories).arel.to_sql).to eql(result)
      end

      it 'allows connect to be set to something different using a single value' do
        klass.send(:recursive_auxiliary_statement, :all_categories) do |cte|
          cte.query Category.all
          cte.join id: :parent_id
          cte.connect :name
        end

        result = 'WITH RECURSIVE "all_categories" AS ('
        result << ' SELECT "categories"."name", "categories"."parent_id"'
        result << ' FROM "categories"'
        result << ' WHERE "categories"."parent_name" IS NULL'
        result << ' UNION'
        result << ' SELECT "categories"."name", "categories"."parent_id"'
        result << ' FROM "categories", "all_categories"'
        result << ' WHERE "categories"."parent_name" = "all_categories"."name"'
        result << ' ) SELECT "courses".* FROM "courses" INNER JOIN "all_categories"'
        result << ' ON "all_categories"."parent_id" = "courses"."id"'
        expect(subject.with(:all_categories).arel.to_sql).to eql(result)
      end

      it 'allows a complete different set of connect' do
        klass.send(:recursive_auxiliary_statement, :all_categories) do |cte|
          cte.query Category.all
          cte.join id: :parent_id
          cte.connect left: :right
        end

        result = 'WITH RECURSIVE "all_categories" AS ('
        result << ' SELECT "categories"."left", "categories"."parent_id"'
        result << ' FROM "categories"'
        result << ' WHERE "categories"."right" IS NULL'
        result << ' UNION'
        result << ' SELECT "categories"."left", "categories"."parent_id"'
        result << ' FROM "categories", "all_categories"'
        result << ' WHERE "categories"."right" = "all_categories"."left"'
        result << ' ) SELECT "courses".* FROM "courses" INNER JOIN "all_categories"'
        result << ' ON "all_categories"."parent_id" = "courses"."id"'
        expect(subject.with(:all_categories).arel.to_sql).to eql(result)
      end

      it 'allows using an union all' do
        klass.send(:recursive_auxiliary_statement, :all_categories) do |cte|
          cte.query Category.all
          cte.join id: :parent_id
          cte.union_all!
        end

        result = 'WITH RECURSIVE "all_categories" AS ('
        result << ' SELECT "categories"."id", "categories"."parent_id"'
        result << ' FROM "categories"'
        result << ' WHERE "categories"."parent_id" IS NULL'
        result << ' UNION ALL'
        result << ' SELECT "categories"."id", "categories"."parent_id"'
        result << ' FROM "categories", "all_categories"'
        result << ' WHERE "categories"."parent_id" = "all_categories"."id"'
        result << ' ) SELECT "courses".* FROM "courses" INNER JOIN "all_categories"'
        result << ' ON "all_categories"."parent_id" = "courses"."id"'
        expect(subject.with(:all_categories).arel.to_sql).to eql(result)
      end

      it 'allows having a complete different initiator' do
        klass.send(:recursive_auxiliary_statement, :all_categories) do |cte|
          cte.query Category.where(parent_id: 5)
          cte.join id: :parent_id
        end

        result = 'WITH RECURSIVE "all_categories" AS ('
        result << ' SELECT "categories"."id", "categories"."parent_id"'
        result << ' FROM "categories"'
        result << ' WHERE "categories"."parent_id" = $1'
        result << ' UNION'
        result << ' SELECT "categories"."id", "categories"."parent_id"'
        result << ' FROM "categories", "all_categories"'
        result << ' WHERE "categories"."parent_id" = "all_categories"."id"'
        result << ' ) SELECT "courses".* FROM "courses" INNER JOIN "all_categories"'
        result << ' ON "all_categories"."parent_id" = "courses"."id"'
        expect(subject.with(:all_categories).arel.to_sql).to eql(result)
      end

      it 'can process the depth of the query' do
        klass.send(:recursive_auxiliary_statement, :all_categories) do |cte|
          cte.query Category.all
          cte.join id: :parent_id
          cte.with_depth
        end

        result = 'WITH RECURSIVE "all_categories" AS ('
        result << ' SELECT "categories"."id", "categories"."parent_id", 0 AS depth'
        result << ' FROM "categories"'
        result << ' WHERE "categories"."parent_id" IS NULL'
        result << ' UNION'
        result << ' SELECT "categories"."id", "categories"."parent_id", ("all_categories"."depth" + 1) AS depth'
        result << ' FROM "categories", "all_categories"'
        result << ' WHERE "categories"."parent_id" = "all_categories"."id"'
        result << ' ) SELECT "courses".* FROM "courses" INNER JOIN "all_categories"'
        result << ' ON "all_categories"."parent_id" = "courses"."id"'
        expect(subject.with(:all_categories).arel.to_sql).to eql(result)
      end

      it 'can process and expose the depth of the query' do
        klass.send(:recursive_auxiliary_statement, :all_categories) do |cte|
          cte.query Category.all
          cte.join id: :parent_id
          cte.with_depth 'd', start: 10, as: :category_depth
        end

        result = 'WITH RECURSIVE "all_categories" AS ('
        result << ' SELECT "categories"."id", "categories"."parent_id", 10 AS d'
        result << ' FROM "categories"'
        result << ' WHERE "categories"."parent_id" IS NULL'
        result << ' UNION'
        result << ' SELECT "categories"."id", "categories"."parent_id", ("all_categories"."d" + 1) AS d'
        result << ' FROM "categories", "all_categories"'
        result << ' WHERE "categories"."parent_id" = "all_categories"."id"'
        result << ' ) SELECT "courses".*, "all_categories"."d" AS category_depth FROM "courses" INNER JOIN "all_categories"'
        result << ' ON "all_categories"."parent_id" = "courses"."id"'
        expect(subject.with(:all_categories).arel.to_sql).to eql(result)
      end

      it 'can process the path of the query' do
        klass.send(:recursive_auxiliary_statement, :all_categories) do |cte|
          cte.query Category.all
          cte.join id: :parent_id
          cte.with_path
        end

        result = 'WITH RECURSIVE "all_categories" AS ('
        result << ' SELECT "categories"."id", "categories"."parent_id", ARRAY["categories"."id"]::varchar[] AS path'
        result << ' FROM "categories"'
        result << ' WHERE "categories"."parent_id" IS NULL'
        result << ' UNION'
        result << ' SELECT "categories"."id", "categories"."parent_id", array_append("all_categories"."path", "categories"."id"::varchar) AS path'
        result << ' FROM "categories", "all_categories"'
        result << ' WHERE "categories"."parent_id" = "all_categories"."id"'
        result << ' ) SELECT "courses".* FROM "courses" INNER JOIN "all_categories"'
        result << ' ON "all_categories"."parent_id" = "courses"."id"'
        expect(subject.with(:all_categories).arel.to_sql).to eql(result)
      end

      it 'can process and expose the path of the query' do
        klass.send(:recursive_auxiliary_statement, :all_categories) do |cte|
          cte.query Category.all
          cte.join id: :parent_id
          cte.with_path 'p', source: :name, as: :category_path
        end

        result = 'WITH RECURSIVE "all_categories" AS ('
        result << ' SELECT "categories"."id", "categories"."parent_id", ARRAY["categories"."name"]::varchar[] AS p'
        result << ' FROM "categories"'
        result << ' WHERE "categories"."parent_id" IS NULL'
        result << ' UNION'
        result << ' SELECT "categories"."id", "categories"."parent_id", array_append("all_categories"."p", "categories"."name"::varchar) AS p'
        result << ' FROM "categories", "all_categories"'
        result << ' WHERE "categories"."parent_id" = "all_categories"."id"'
        result << ' ) SELECT "courses".*, "all_categories"."p" AS category_path FROM "courses" INNER JOIN "all_categories"'
        result << ' ON "all_categories"."parent_id" = "courses"."id"'
        expect(subject.with(:all_categories).arel.to_sql).to eql(result)
      end

      it 'works with string queries' do
        klass.send(:recursive_auxiliary_statement, :all_categories) do |cte|
          cte.query 'SELECT * FROM categories WHERE a IS NULL'
          cte.sub_query 'SELECT * FROM categories, all_categories WHERE all_categories.a = b'
          cte.join id: :parent_id
        end

        result = 'WITH RECURSIVE "all_categories" AS ('
        result << 'SELECT * FROM categories WHERE a IS NULL'
        result << ' UNION '
        result << ' SELECT * FROM categories, all_categories WHERE all_categories.a = b'
        result << ') SELECT "courses".* FROM "courses" INNER JOIN "all_categories"'
        result << ' ON "all_categories"."parent_id" = "courses"."id"'
        expect(subject.with(:all_categories).arel.to_sql).to eql(result)
      end

      it 'raises an error when query is a string and there is no sub query' do
        klass.send(:recursive_auxiliary_statement, :all_categories) do |cte|
          cte.query 'SELECT * FROM categories WHERE a IS NULL'
          cte.join id: :parent_id
        end

        expect{ subject.with(:all_categories).arel.to_sql }.to raise_error(ArgumentError, /generate sub query/)
      end

      it 'raises an error when sub query has an invalid type' do
        klass.send(:recursive_auxiliary_statement, :all_categories) do |cte|
          cte.query 'SELECT * FROM categories WHERE a IS NULL'
          cte.sub_query -> { 1 }
          cte.join id: :parent_id
        end

        expect{ subject.with(:all_categories).arel.to_sql }.to raise_error(ArgumentError, /query and sub query objects/)
      end

      it 'raises an error when connect can be resolved automatically' do
        allow(klass).to receive(:primary_key).and_return(nil)
        klass.send(:recursive_auxiliary_statement, :all_categories) do |cte|
          cte.query Category.all
          cte.join id: :parent_id
        end

        expect{ subject.with(:all_categories).arel.to_sql }.to raise_error(ArgumentError, /setting up a proper way to connect/)
      end
    end

    it 'works with count and does not add extra columns' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes content: :comment_content
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT "comments"."content" AS comment_content, "comments"."user_id" FROM "comments")'
      result << ' SELECT COUNT(*) FROM "users"'
      result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'

      query = get_last_executed_query{ subject.with(:comments).count }
      expect(query).to eql(result)
    end

    it 'works with sum and does not add extra columns' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes id: :value
      end

      result = 'WITH "comments" AS'
      result << ' (SELECT "comments"."id" AS value, "comments"."user_id" FROM "comments")'
      result << ' SELECT SUM("comments"."value") FROM "users"'
      result << ' INNER JOIN "comments" ON "comments"."user_id" = "users"."id"'

      query = get_last_executed_query{ subject.with(:comments).sum(comments: :value) }
      expect(query).to eql(result)
    end

    it 'raises an error when using an invalid type of object as query' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query :string, String
      end

      expect{ subject.with(:comments).arel.to_sql }.to raise_error(ArgumentError, /object types/)
    end

    it 'raises an error when trying to use a statement that is not defined' do
      expect{ subject.with(:does_not_exist).arel.to_sql }.to raise_error(ArgumentError)
    end

    it 'raises an error when using an invalid type of join' do
      klass.send(:auxiliary_statement, :comments) do |cte|
        cte.query Comment.all
        cte.attributes content: :comment_content
        cte.join_type :invalid
      end

      expect{ subject.with(:comments).arel.to_sql }.to raise_error(ArgumentError)
    end
  end

  context 'on model' do
    subject { User }

    it 'has its configurator' do
      expect(subject.protected_methods).to include(:cte)
      expect(subject.protected_methods).to include(:auxiliary_statement)
    end

    it 'has the recursive configuration' do
      expect(subject.protected_methods).to include(:recursive_cte)
      expect(subject.protected_methods).to include(:recursive_auxiliary_statement)
    end

    it 'allows configure new auxiliary statements' do
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

  context 'on external' do
    let(:klass) { Torque::PostgreSQL::AuxiliaryStatement }
    subject { User }

    it 'has the external method available' do
      expect(klass).to respond_to(:create)
    end

    it 'accepts simple auxiliary statement definition' do
      sample = klass.create(Comment.all)
      query = subject.with(sample, select: {content: :comment_content}).arel.to_sql

      result = 'WITH "comment" AS'
      result << ' (SELECT "comments"."content" AS comment_content, "comments"."user_id" FROM "comments")'
      result << ' SELECT "users".*, "comment"."comment_content" FROM "users"'
      result << ' INNER JOIN "comment" ON "comment"."user_id" = "users"."id"'
      expect(query).to eql(result)
    end

    it 'accepts a hash auxiliary statement definition' do
      sample = klass.create(query: Comment.all, select: {content: :comment_content})
      query = subject.with(sample).arel.to_sql

      result = 'WITH "comment" AS'
      result << ' (SELECT "comments"."content" AS comment_content, "comments"."user_id" FROM "comments")'
      result << ' SELECT "users".*, "comment"."comment_content" FROM "users"'
      result << ' INNER JOIN "comment" ON "comment"."user_id" = "users"."id"'
      expect(query).to eql(result)
    end

    it 'accepts a block when creating the auxiliary statement' do
      sample = klass.create(:all_comments) do |cte|
        cte.query Comment.all
        cte.select content: :comment_content
      end

      result = 'WITH "all_comments" AS'
      result << ' (SELECT "comments"."content" AS comment_content, "comments"."user_id" FROM "comments")'
      result << ' SELECT "users".*, "all_comments"."comment_content" FROM "users"'
      result << ' INNER JOIN "all_comments" ON "all_comments"."user_id" = "users"."id"'

      query = subject.with(sample).arel.to_sql
      expect(query).to eql(result)
    end

    context 'recursive' do
      let(:klass) { Torque::PostgreSQL::AuxiliaryStatement::Recursive }
      subject { Course }

      it 'has the external method available' do
        expect(klass).to respond_to(:create)
      end

      it 'accepts simple recursive auxiliary statement definition' do
        settings = { join: { id: :parent_id } }
        query = subject.with(klass.create(Category.all), **settings).arel.to_sql

        result = 'WITH RECURSIVE "category" AS ('
        result << ' SELECT "categories"."id", "categories"."parent_id"'
        result << ' FROM "categories"'
        result << ' WHERE "categories"."parent_id" IS NULL'
        result << ' UNION'
        result << ' SELECT "categories"."id", "categories"."parent_id"'
        result << ' FROM "categories", "category"'
        result << ' WHERE "categories"."parent_id" = "category"."id"'
        result << ' ) SELECT "courses".* FROM "courses" INNER JOIN "category"'
        result << ' ON "category"."parent_id" = "courses"."id"'
        expect(query).to eql(result)
      end

      it 'accepts a connect option' do
        settings = { join: { id: :parent_id }, connect: { a: :b } }
        query = subject.with(klass.create(Category.all), **settings).arel.to_sql

        result = 'WITH RECURSIVE "category" AS ('
        result << ' SELECT "categories"."a", "categories"."parent_id"'
        result << ' FROM "categories"'
        result << ' WHERE "categories"."b" IS NULL'
        result << ' UNION'
        result << ' SELECT "categories"."a", "categories"."parent_id"'
        result << ' FROM "categories", "category"'
        result << ' WHERE "categories"."b" = "category"."a"'
        result << ' ) SELECT "courses".* FROM "courses" INNER JOIN "category"'
        result << ' ON "category"."parent_id" = "courses"."id"'
        expect(query).to eql(result)
      end

      it 'accepts an union all option' do
        settings = { join: { id: :parent_id }, union_all: true }
        query = subject.with(klass.create(Category.all), **settings).arel.to_sql

        result = 'WITH RECURSIVE "category" AS ('
        result << ' SELECT "categories"."id", "categories"."parent_id"'
        result << ' FROM "categories"'
        result << ' WHERE "categories"."parent_id" IS NULL'
        result << ' UNION ALL'
        result << ' SELECT "categories"."id", "categories"."parent_id"'
        result << ' FROM "categories", "category"'
        result << ' WHERE "categories"."parent_id" = "category"."id"'
        result << ' ) SELECT "courses".* FROM "courses" INNER JOIN "category"'
        result << ' ON "category"."parent_id" = "courses"."id"'
        expect(query).to eql(result)
      end

      it 'accepts a sub query option' do
        settings = { join: { id: :parent_id }, sub_query: Category.where(active: true) }
        query = subject.with(klass.create(Category.all), **settings).arel.to_sql

        result = 'WITH RECURSIVE "category" AS ('
        result << ' SELECT "categories"."id", "categories"."parent_id" FROM "categories"'
        result << ' UNION'
        result << ' SELECT "categories"."id", "categories"."parent_id" FROM "categories", "category" WHERE "categories"."active" = $1'
        result << ' ) SELECT "courses".* FROM "courses" INNER JOIN "category"'
        result << ' ON "category"."parent_id" = "courses"."id"'
        expect(query).to eql(result)
      end

      it 'accepts a depth option' do
        settings = { join: { id: :parent_id }, with_depth: { name: 'a', start: 5, as: 'b' } }
        query = subject.with(klass.create(Category.all), **settings).arel.to_sql

        result = 'WITH RECURSIVE "category" AS ('
        result << ' SELECT "categories"."id", "categories"."parent_id", 5 AS a'
        result << ' FROM "categories"'
        result << ' WHERE "categories"."parent_id" IS NULL'
        result << ' UNION'
        result << ' SELECT "categories"."id", "categories"."parent_id", ("category"."a" + 1) AS a'
        result << ' FROM "categories", "category"'
        result << ' WHERE "categories"."parent_id" = "category"."id"'
        result << ' ) SELECT "courses".*, "category"."a" AS b FROM "courses" INNER JOIN "category"'
        result << ' ON "category"."parent_id" = "courses"."id"'
        expect(query).to eql(result)
      end

      it 'accepts a path option' do
        settings = { join: { id: :parent_id }, with_path: { name: 'a', source: 'b', as: 'c' } }
        query = subject.with(klass.create(Category.all), **settings).arel.to_sql

        result = 'WITH RECURSIVE "category" AS ('
        result << ' SELECT "categories"."id", "categories"."parent_id", ARRAY["categories"."b"]::varchar[] AS a'
        result << ' FROM "categories"'
        result << ' WHERE "categories"."parent_id" IS NULL'
        result << ' UNION'
        result << ' SELECT "categories"."id", "categories"."parent_id", array_append("category"."a", "categories"."b"::varchar) AS a'
        result << ' FROM "categories", "category"'
        result << ' WHERE "categories"."parent_id" = "category"."id"'
        result << ' ) SELECT "courses".*, "category"."a" AS c FROM "courses" INNER JOIN "category"'
        result << ' ON "category"."parent_id" = "courses"."id"'
        expect(query).to eql(result)
      end
    end
  end

  context 'on settings' do
    let(:base) { User }
    let(:statement_klass) do
      base.send(:auxiliary_statement, :statement)
      base::Statement_AuxiliaryStatement
    end

    subject do
      Torque::PostgreSQL::AuxiliaryStatement::Settings.new(base, statement_klass)
    end

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
      expect{ subject.with(:comments).arel.to_sql }.to raise_error(StandardError)
    end
  end
end
