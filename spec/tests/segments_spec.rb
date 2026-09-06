require 'spec_helper'

RSpec.describe 'Segments', type: :helper do
  let(:source) { User.all }
  let(:ages) { { adults: { age: 18.. }, minors: { age: ...18 } } }

  context 'on relation' do
    it 'produces one filtered aggregate per segment' do
      sql, binds = get_query_with_binds { source.segments(**ages).count }

      expect(sql).to include(<<~SQL.squish)
        SELECT COUNT(*) FILTER (WHERE "users"."age" >= $1) AS "adults",
        COUNT(*) FILTER (WHERE "users"."age" < $2) AS "minors" FROM "users"
      SQL
      expect(binds.map(&:value)).to eq([18, 18])
    end

    it 'counts each segment' do
      create(:user, age: 5)
      create(:user, age: 15)
      create(:user, age: 25)

      expect(source.segments(**ages).count).to eq(adults: 1, minors: 2)
    end

    it 'leaves the aggregate unfiltered for nil and blank conditions' do
      create(:user, age: 5)
      create(:user, age: 25)

      query = source.segments(all: nil, none: {}, empty: '', list: [], adults: { age: 18.. })
      sql, = get_query_with_binds { query.count }

      expect(sql).to include(<<~SQL.squish)
        SELECT COUNT(*) AS "all", COUNT(*) AS "none", COUNT(*) AS "empty", COUNT(*) AS "list",
        COUNT(*) FILTER (WHERE "users"."age" >= $1) AS "adults"
      SQL
      expect(query.count).to eq(all: 2, none: 2, empty: 2, list: 2, adults: 1)
    end

    it 'applies the filters to other aggregates' do
      create(:user, age: 5)
      create(:user, age: 15)
      create(:user, age: 25)

      query = source.segments(**ages)
      sql, = get_query_with_binds { query.sum(:age) }

      expect(sql).to include('SUM("users"."age") FILTER (WHERE "users"."age" >= $1) AS "adults"')
      expect(query.sum(:age)).to eq(adults: 25, minors: 20)
      expect(query.average(:age)).to eq(adults: 25, minors: 10)
      expect(query.maximum(:age)).to eq(adults: 25, minors: 15)
    end

    it 'returns zero for sums over empty segments' do
      create(:user, age: 5)

      expect(source.segments(**ages).sum(:age)).to eq(adults: 0, minors: 5)
    end

    it 'drops the order when there is no grouping' do
      sql, = get_query_with_binds { source.order(:name).segments(**ages).count }
      expect(sql).not_to include('ORDER BY')
    end

    it 'does not change how records are loaded' do
      user = create(:user, age: 5)
      expect(source.segments(**ages).to_a).to eq([user])
    end

    it 'is available on the model class' do
      expect(User.segments(**ages)).to be_a(ActiveRecord::Relation)
    end
  end

  context 'on grouping' do
    it 'nests the segments under each group key' do
      create(:user, age: 5, role: :visitor)
      create(:user, age: 25, role: :visitor)
      create(:user, age: 25, role: :admin)

      result = source.group(:role).segments(**ages).count
      expect(result.keys).to match_array(source.group(:role).count.keys)
      expect(result['visitor']).to eq(adults: 1, minors: 1)
      expect(result['admin']).to eq(adults: 1, minors: 0)
    end

    it 'uses array keys for multiple groups' do
      create(:user, age: 5, role: :visitor, name: 'a')
      create(:user, age: 25, role: :visitor, name: 'a')

      result = source.group(:role, :name).segments(**ages).count
      expect(result).to eq(['visitor', 'a'] => { adults: 1, minors: 1 })
    end

    it 'accepts raw expressions as groups' do
      create(:user, age: 5)
      create(:user, age: 25)

      result = source.group('"users"."age" >= 18').segments(**ages).count
      expect(result).to eq(false => { adults: 0, minors: 1 }, true => { adults: 1, minors: 0 })
    end

    it 'composes with buckets' do
      create(:user, age: 5, role: :visitor)
      create(:user, age: 15, role: :admin)
      create(:user, age: 25, role: :admin)

      query = source.buckets(:age, 0..50, count: 5).segments(admins: { role: :admin }, visitors: { role: :visitor })
      expect(query.count).to eq(
        0...10 => { admins: 0, visitors: 1 },
        10...20 => { admins: 1, visitors: 0 },
        20...30 => { admins: 1, visitors: 0 },
      )
    end
  end

  context 'on conditions' do
    let(:source) { Post.all }

    it 'accepts where arguments' do
      query = source.segments(text: 'title IS NOT NULL', bound: [['title = ?', 'a']])
      sql, binds = get_query_with_binds { query.count }

      expect(sql).to include('FILTER (WHERE (title IS NOT NULL)) AS "text"')
      expect(sql).to include('FILTER (WHERE (title = $1)) AS "bound"')
      expect(binds).to eq(['a'])
    end

    it 'applies each item of an array in order' do
      condition = [:test_scope, { status: :draft }, -> { where.not(title: nil) }, Post.where(author_id: 1)]
      sql, = get_query_with_binds { source.segments(mixed: condition).count }

      expect(sql).to include(<<~SQL.squish)
        FILTER (WHERE (1=1) AND "posts"."status" = $1 AND "posts"."title" IS NOT NULL
        AND "posts"."author_id" = $2) AS "mixed"
      SQL
    end

    it 'skips blank items of an array' do
      sql, = get_query_with_binds { source.segments(drafts: [nil, {}, { status: :draft }]).count }
      expect(sql).to include(%{FILTER (WHERE "posts"."status" = $1) AS "drafts"})
    end

    it 'accepts a scope name' do
      sql, = get_query_with_binds { source.segments(tested: :test_scope).count }
      expect(sql).to include('FILTER (WHERE (1=1)) AS "tested"')
    end

    it 'accepts a relation' do
      sql, = get_query_with_binds { source.segments(drafts: Post.where(status: :draft)).count }
      expect(sql).to include(%{FILTER (WHERE "posts"."status" = $1) AS "drafts"})
    end

    it 'accepts a proc evaluated on the model' do
      sql, = get_query_with_binds { source.segments(drafts: -> { where(status: :draft) }).count }
      expect(sql).to include(%{FILTER (WHERE "posts"."status" = $1) AS "drafts"})
    end

    it 'accepts a proc receiving the model relation' do
      sql, = get_query_with_binds { source.segments(drafts: ->(posts) { posts.where(status: :draft) }).count }
      expect(sql).to include(%{FILTER (WHERE "posts"."status" = $1) AS "drafts"})
    end

    it 'accepts an arel predicate' do
      sql, = get_query_with_binds { source.segments(titled: Post.arel_table[:title].not_eq(nil)).count }
      expect(sql).to include(%{FILTER (WHERE "posts"."title" IS NOT NULL) AS "titled"})
    end

    it 'raises when a condition does not filter anything' do
      expect { source.segments(all: Post.all) }.to raise_error(ArgumentError, /does not filter/)
      expect { source.segments(all: -> { order(:title) }) }.to raise_error(ArgumentError, /does not filter/)
      expect { source.segments(all: [:test_scope, nil]) }.not_to raise_error
    end
  end

  context 'on sanity' do
    before do
      create(:user, age: 5, role: :visitor)
      create(:user, age: 25, role: :visitor)
      create(:user, age: 25, role: :admin)
    end

    it 'keeps the conditions of the query' do
      query = source.where(role: :visitor).segments(**ages)
      sql, = get_query_with_binds { query.count }

      expect(sql).to include(%{FROM "users" WHERE "users"."role" = $3})
      expect(query.count).to eq(adults: 1, minors: 1)
      expect(query.where(age: 25).count).to eq(adults: 1, minors: 0)
    end

    it 'keeps joins and accepts conditions on joined tables' do
      create(:comment, user: User.find_by(age: 5))
      create(:comment, user: User.find_by(role: :admin))

      query = Comment.joins(:user).segments(adults: { users: { age: 18.. } }, minors: { users: { age: ...18 } })
      sql, = get_query_with_binds { query.count }

      expect(sql).to include(%{INNER JOIN "users" ON "users"."id" = "comments"."user_id"})
      expect(query.count).to eq(adults: 1, minors: 1)
    end

    it 'goes through eager loading' do
      create(:comment, user: User.find_by(age: 5))
      create(:comment, user: User.find_by(role: :admin))

      query = Comment.includes(:user).where(users: { role: :visitor })
      query = query.segments(adults: { users: { age: 18.. } }, minors: { users: { age: ...18 } })
      sql, = get_query_with_binds { query.count }

      expect(sql).to include('LEFT OUTER JOIN "users"')
      expect(query.count).to eq(adults: 0, minors: 1)
    end

    it 'counts a column and distinct values' do
      query = source.segments(**ages)

      sql, = get_query_with_binds { query.count(:name) }
      expect(sql).to include('COUNT("users"."name") FILTER')

      sql, = get_query_with_binds { query.distinct.count }
      expect(sql).to include('COUNT(DISTINCT "users"."id") FILTER')
      expect(query.distinct.count).to eq(adults: 2, minors: 1)
    end

    it 'works asynchronously' do
      expect(source.segments(**ages).async_count.value).to eq(adults: 2, minors: 1)
    end

    it 'does not affect operations other than calculations' do
      query = source.segments(**ages)

      expect(query.to_sql).to eq('SELECT "users".* FROM "users"')
      expect(query.size).to eq(adults: 2, minors: 1)
      expect(query.exists?).to be(true)
      expect(query.pluck(:age)).to match_array([5, 25, 25])
      expect(query.order(:age).first.age).to eq(5)
      expect(query.update_all(name: 'x')).to eq(3)
      expect(query.where(age: 5).delete_all).to eq(1)
    end

    it 'does not affect calculations without segments' do
      expect(source.count).to eq(3)
      expect(source.group(:role).count).to eq('visitor' => 2, 'admin' => 1)
    end
  end

  context 'on composing' do
    it 'merges chained calls' do
      query = source.segments(adults: ages[:adults]).segments(minors: ages[:minors])
      expect(query.segments_value.keys).to eq(%i[adults minors])
    end

    it 'merges segments from another relation' do
      query = source.segments(adults: ages[:adults]).merge(User.segments(minors: ages[:minors]))
      expect(query.segments_value.keys).to eq(%i[adults minors])
    end

    it 'can be unscoped' do
      create(:user, age: 5)
      expect(source.segments(**ages).unscope(:segments).count).to eq(1)
    end
  end
end
