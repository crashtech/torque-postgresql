require 'spec_helper'

RSpec::Matchers.define :be_attributes_as do |list|
  match do |other|
    other.each_with_index.map do |item, idx|
      item.relation.name == list[idx][0] && item.name.to_s == list[idx][1]
    end.all?
  end
end

RSpec.describe 'Relation', type: :helper do

  context 'on resolving columns' do
    subject { Post.unscoped.method(:resolve_column) }

    def attribute(relation, name)
      result = Arel::Attributes::Attribute.new
      result.relation = relation
      result.name = name
      result
    end

    it 'asserts sql literals' do
      check = ['name', 'other.title']
      expect(subject.call(check)).to eql(check)
    end

    it 'asserts attribute symbols' do
      check = [:title, :content]
      result = [['posts', 'title'], ['posts', 'content']]
      expect(subject.call(check)).to be_attributes_as(result)
    end

    it 'asserts direct hash relations' do
      check = [:title, author: :name]
      result = [['posts', 'title'], ['authors', 'name']]
      expect(subject.call(check)).to be_attributes_as(result)
    end

    it 'asserts multiple values on hash definition' do
      check = [author: [:name, :age]]
      result = [['authors', 'name'], ['authors', 'age']]
      expect(subject.call(check)).to be_attributes_as(result)
    end

    it 'raises on relation not present' do
      check = [supervisors: :name]
      expect{ subject.call(check) }.to raise_error(ArgumentError, /Relation for/)
    end

    it 'raises on third level access' do
      check = [author: [comments: :body]]
      expect{ subject.call(check) }.to raise_error(ArgumentError, /on third level/)
    end
  end

  context 'on joining series' do
    let(:source) { Video.all }

    it 'works' do
      list = create_list(:video, 5)[1..4]
      range = list.first.id..list.last.id
      expect(source.join_series(range, with: :id).to_a).to eq(list)
      expect(source.join_series(range, with: :id, step: 3).to_a).to eq([list.first, list.last])
    end

    it 'produces the right SQL' do
      sql = 'SELECT "videos".* FROM "videos"'
      sql += ' INNER JOIN GENERATE_SERIES(1::integer, 10::integer)'
      sql += ' AS series ON "series" = "videos"."id"'
      expect(source.join_series(1..10, with: :id).to_sql).to eq(sql)
    end

    it 'can be renamed' do
      sql = 'SELECT "videos".* FROM "videos"'
      sql += ' INNER JOIN GENERATE_SERIES(1::integer, 10::integer)'
      sql += ' AS seq ON "seq" = "videos"."id"'
      expect(source.join_series(1..10, with: :id, as: :seq).to_sql).to eq(sql)
    end

    it 'can contain the step' do
      sql = 'SELECT "videos".* FROM "videos"'
      sql += ' INNER JOIN GENERATE_SERIES(1::integer, 10::integer, 2::integer)'
      sql += ' AS series ON "series" = "videos"."id"'
      expect(source.join_series(1..10, with: :id, step: 2).to_sql).to eq(sql)
    end

    it 'works with float values' do
      sql = 'SELECT "videos".* FROM "videos"'
      sql += ' INNER JOIN GENERATE_SERIES(1.0::numeric, 10.0::numeric, 0.5::numeric)'
      sql += ' AS series ON "series" = "videos"."id"'
      expect(source.join_series(1.0..10.0, with: :id, step: 0.5).to_sql).to eq(sql)
    end

    it 'works with time values' do
      sql = 'SELECT "videos".* FROM "videos"'
      sql += ' INNER JOIN GENERATE_SERIES('
      sql += "'2025-01-01 00:00:00'::timestamp, '2025-01-01 01:00:00'::timestamp"
      sql += ", 'PT1M'::interval"
      sql += ') AS series ON "series" = "videos"."created_at"'
      range = (Time.utc(2025, 1, 1, 0)..Time.utc(2025, 1, 1, 1))
      expect(source.join_series(range, with: :created_at, step: 1.minute).to_sql).to eq(sql)
    end

    it 'works with date values' do
      sql = 'SELECT "videos".* FROM "videos"'
      sql += ' INNER JOIN GENERATE_SERIES('
      sql += "'2025-01-01 00:00:00'::timestamp, '2025-01-02 00:00:00'::timestamp"
      sql += ", 'P1D'::interval"
      sql += ') AS series ON "series" = "videos"."created_at"'
      range = (Date.new(2025, 1, 1)..Date.new(2025, 1, 2))
      expect(source.join_series(range, with: :created_at, step: 1.day).to_sql).to eq(sql)
    end

    it 'works with time with zones values' do
      sql = 'SELECT "videos".* FROM "videos"'
      sql += ' INNER JOIN GENERATE_SERIES('
      sql += "'2025-01-01 00:00:00'::timestamptz, '2025-01-01 01:00:00'::timestamptz"
      sql += ", 'PT1M'::interval"
      sql += ') AS series ON "series" = "videos"."id"'
      left = ActiveSupport::TimeZone['UTC'].local(2025, 1, 1, 0)
      right = ActiveSupport::TimeZone['UTC'].local(2025, 1, 1, 1)
      expect(source.join_series(left..right, with: :id, step: 1.minute).to_sql).to eq(sql)
    end

    it 'can provide the additional time zone value' do
      sql = 'SELECT "videos".* FROM "videos"'
      sql += ' INNER JOIN GENERATE_SERIES('
      sql += "'2025-01-01 00:00:00'::timestamptz, '2025-01-01 01:00:00'::timestamptz"
      sql += ", 'PT1M'::interval, 'UTC'::text"
      sql += ') AS series ON "series" = "videos"."id"'
      left = ActiveSupport::TimeZone['UTC'].local(2025, 1, 1, 0)
      right = ActiveSupport::TimeZone['UTC'].local(2025, 1, 1, 1)

      query = source.join_series(left..right, with: :id, step: 1.minute, time_zone: 'UTC')
      expect(query.to_sql).to eq(sql)
    end

    it 'can use other types of joins' do
      sql = ' LEFT OUTER JOIN GENERATE_SERIES(1::integer, 10::integer)'
      expect(source.join_series(1..10, with: :id, mode: :left).to_sql).to include(sql)

      sql = ' RIGHT OUTER JOIN GENERATE_SERIES(1::integer, 10::integer)'
      expect(source.join_series(1..10, with: :id, mode: :right).to_sql).to include(sql)

      sql = ' FULL OUTER JOIN GENERATE_SERIES(1::integer, 10::integer)'
      expect(source.join_series(1..10, with: :id, mode: :full).to_sql).to include(sql)
    end

    it 'supports a complex way of joining' do
      query = source.join_series(1..10) do |series, table|
        table['id'].lteq(series)
      end

      sql = 'SELECT "videos".* FROM "videos"'
      sql += ' INNER JOIN GENERATE_SERIES(1::integer, 10::integer)'
      sql += ' AS series ON "videos"."id" <= "series"'
      expect(query.to_sql).to eq(sql)
    end

    it 'properly binds all provided values' do
      query = source.join_series(1..10, with: :id, step: 2)
      sql, binds = get_query_with_binds { query.load }

      expect(sql).to include('GENERATE_SERIES($1::integer, $2::integer, $3::integer)')
      expect(binds.map(&:value)).to eq([1, 10, 2])
    end

    context 'on errors' do
      it 'does not support non-range values' do
        expect do
          source.join_series(1, with: :id)
        end.to raise_error(ArgumentError, /Range/)
      end

      it 'does not support beginless ranges' do
        expect do
          source.join_series(..10, with: :id)
        end.to raise_error(ArgumentError, /Beginless/)
      end

      it 'does not support endless ranges' do
        expect do
          source.join_series(1.., with: :id)
        end.to raise_error(ArgumentError, /Endless/)
      end

      it 'requires a step when using non-numeric ranges' do
        range = Date.new(2025, 1, 1)..Date.new(2025, 1, 10)
        expect do
          source.join_series(range, with: :id)
        end.to raise_error(ArgumentError, /:step/)
      end

      it 'has strict type of join support' do
        expect do
          source.join_series(1..10, with: :id, mode: :cross)
        end.to raise_error(ArgumentError, /join type/)
      end

      it 'requires a :with keyword' do
        expect do
          source.join_series(1..10)
        end.to raise_error(ArgumentError, /:with/)
      end

      it 'does not support unexpected values' do
        expect do
          source.join_series(1..10, step: :other)
        end.to raise_error(ArgumentError, /value type/)
      end
    end
  end

  context 'on buckets' do
    let(:source) { User.all }

    it 'produces the right query' do
      query = source.buckets(:age, 0..50, size: 5)
      sql, binds = get_query_with_binds { query.load }

      expect(sql).to include(<<~SQL.squish)
        WIDTH_BUCKET("users"."age", $1::numeric, $2::numeric, $3::integer) AS bucket
      SQL
      expect(binds.map(&:value)).to eq([0, 50, 5])
    end

    it 'can query records by buckets' do
      list = [create(:user, age: 5), create(:user, age: 5), create(:user, age: 15)]
      query = source.buckets(:age, 0..50, size: 5).records

      expect(query).to be_a(Hash)
      expect(query.keys).to match_array([0...10, 10...20])
      expect(query[0...10]).to match_array([list[0], list[1]])
      expect(query[10...20]).to match_array([list[2]])
    end

    it 'can query buckets of roles' do
      list = [create(:user, role: :visitor)]
      list << create(:user, role: :assistant)
      list << create(:user, role: :manager)
      query = source.buckets(:role, %w[assistant manager], cast: :roles).records

      expect(query).to be_a(Hash)
      expect(query.keys).to match_array([nil, 'assistant', 'manager'])
      expect(query[nil]).to eq([list[0]])
      expect(query['assistant']).to eq([list[1]])
      expect(query['manager']).to eq([list[2]])
    end

    it 'works with calculations' do
      list = [create(:user, age: 5), create(:user, age: 5), create(:user, age: 15)]
      query = source.buckets(:age, 0..50, size: 5).count

      expect(query).to be_a(Hash)
      expect(query.keys).to match_array([0...10, 10...20])
      expect(query[0...10]).to eq(2)
      expect(query[10...20]).to eq(1)
    end

    it 'works with other types of calculations' do
      list = [create(:user, age: 5), create(:user, age: 5), create(:user, age: 15)]
      query = source.buckets(:age, 0..50, size: 5).sum(:age)

      expect(query).to be_a(Hash)
      expect(query.keys).to match_array([0...10, 10...20])
      expect(query[0...10]).to eq(10)
      expect(query[10...20]).to eq(15)
    end

    it 'work with joins and merge' do
      list = [create(:user, age: 5), create(:user, age: 5), create(:user, age: 15)]
      records = [create(:comment, user: list[0], content: 'Hello')]
      records << create(:comment, user: list[1], content: 'World')
      records << create(:comment, user: list[2], content: 'Test')

      query = Comment.joins(:user).merge(source.buckets(:age, 0..50, size: 5)).records

      expect(query).to be_a(Hash)
      expect(query.keys).to match_array([0...10, 10...20])
      expect(query[0...10]).to match_array([records[0], records[1]])
      expect(query[10...20]).to match_array([records[2]])
    end
  end

end
