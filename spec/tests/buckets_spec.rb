require 'spec_helper'

RSpec.describe 'Buckets', type: :helper do
  context 'on relation' do
    let(:source) { User.all }

    it 'produces the right query' do
      query = source.buckets(:age, 0..50, count: 5)
      sql, binds = get_query_with_binds { query.load }

      expect(sql).to include(<<~SQL.squish)
        WIDTH_BUCKET("users"."age", $1::numeric, $2::numeric, $3::integer) AS bucket
      SQL
      expect(binds.map(&:value)).to eq([0, 50, 5])
    end

    it 'accepts a part of a column' do
      Profile.create!(name: 'a', settings: { theme: 'dark' })
      Profile.create!(name: 'b', settings: { theme: 'light' })

      query = Profile.buckets({ settings: :theme }, %w[dark light])
      expect(query.to_sql).to include(<<~SQL.squish)
        WIDTH_BUCKET(("profiles"."settings" #>> ARRAY['theme']), ARRAY['dark', 'light']) AS bucket
      SQL

      query = Profile.buckets({ settings: :theme }, %w[dark light])
      expect(query.count).to be_eql('dark' => 1, 'light' => 1)
    end

    it 'can query records by buckets' do
      list = [create(:user, age: 5), create(:user, age: 5), create(:user, age: 15)]
      query = source.buckets(:age, 0..50, count: 5).records

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
      list << create(:user, age: nil)
      query = source.buckets(:age, 0..50, count: 5).count

      expect(query).to be_a(Hash)
      expect(query.keys).to match_array([nil, 0...10, 10...20])
      expect(query[nil]).to eq(1)
      expect(query[0...10]).to eq(2)
      expect(query[10...20]).to eq(1)
    end

    it 'works with other types of calculations' do
      list = [create(:user, age: 5), create(:user, age: 5), create(:user, age: 15)]
      query = source.buckets(:age, 0..50, count: 5).sum(:age)

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

      query = Comment.joins(:user).merge(source.buckets(:age, 0..50, count: 5)).records

      expect(query).to be_a(Hash)
      expect(query.keys).to match_array([0...10, 10...20])
      expect(query[0...10]).to match_array([records[0], records[1]])
      expect(query[10...20]).to match_array([records[2]])
    end

    context 'with dates' do
      let(:keys) { 3.times.map { |add| Date.new(2010 + add) } }
      let(:query) { source.buckets(:created_at, keys, cast: :date) }

      let!(:list) do
        list = [create(:user, created_at: Date.new(2009, 6, 1))]
        list << create(:user, created_at: Date.new(2010, 6, 1))
        list << create(:user, created_at: Date.new(2011, 6, 1))
        list << create(:user, created_at: Date.new(2011, 12, 31))
        list << create(:user, created_at: Date.new(2015, 6, 1))
        list
      end

      it 'produces the right query' do
        expect(query.to_sql).to include(<<~SQL.squish)
          WIDTH_BUCKET("users"."created_at", ARRAY['2010-01-01', '2011-01-01', '2012-01-01']::date[]) AS bucket
        SQL
      end

      it 'outputs the right results' do
        result = query.records
        expect(result.keys).to match_array([nil, *keys])
        expect(result[nil]).to eq([list[0]])
        expect(result[keys[0]]).to eq([list[1]])
        expect(result[keys[1]]).to match_array([list[2], list[3]])
        expect(result[keys[2]]).to eq([list[4]])
      end

      it 'works with count just fine' do
        expect(query.count).to be_eql(nil => 1, keys[0] => 1, keys[1] => 2, keys[2] => 1)
      end
    end
  end
end
