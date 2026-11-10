require 'spec_helper'

RSpec.describe 'PredicateBuilder' do
  describe 'on enumerator lazy' do
    let(:timed_out_error) do
      Torque::PostgreSQL::PredicateBuilder::EnumeratorLazyHandler::Timeout
    end

    subject { Video.all }

    after do
      Torque::PostgreSQL.config.predicate_builder.lazy_timeout = 0.02
      Torque::PostgreSQL.config.predicate_builder.lazy_limit = 2_000
    end

    it 'works with provided value' do
      sql = subject.where(id: [1,2,3].lazy).to_sql
      expect(sql).to include("WHERE \"videos\".\"id\" IN (1, 2, 3)")
    end

    it 'handles gracefully a timeout' do
      Torque::PostgreSQL.config.predicate_builder.lazy_timeout = 0.01
      Torque::PostgreSQL.config.predicate_builder.lazy_limit = nil
      expect { subject.where(id: (1..).lazy).to_sql }.to raise_error(timed_out_error)
    end

    it 'handles properly a limit' do
      Torque::PostgreSQL.config.predicate_builder.lazy_timeout = nil
      Torque::PostgreSQL.config.predicate_builder.lazy_limit = 2

      sql = subject.where(id: [1,2,3].lazy).to_sql
      expect(sql).to include("WHERE \"videos\".\"id\" IN (1, 2)")
    end
  end

  describe 'on arel attribute' do
    subject { Item.all }

    it 'works with both plain attributes' do
      sql = subject.where(id: Item.arel_table[:id]).to_sql
      expect(sql).to include("WHERE \"items\".\"id\" = \"items\".\"id\"")
    end

    it 'works when when the left side is an array' do
      sql = subject.where(tag_ids: Item.arel_table[:id]).to_sql
      expect(sql).to include("WHERE \"items\".\"id\" = ANY(\"items\".\"tag_ids\")")
    end

    it 'works when the right side is an array' do
      sql = subject.where(id: Item.arel_table[:tag_ids]).to_sql
      expect(sql).to include("WHERE \"items\".\"id\" = ANY(\"items\".\"tag_ids\")")
    end

    it 'works when both are arrays' do
      sql = subject.where(tag_ids: Item.arel_table[:tag_ids]).to_sql
      expect(sql).to include("WHERE \"items\".\"tag_ids\" && \"items\".\"tag_ids\"")
    end
  end

  describe 'on array' do
    subject { Item.all }

    before { Torque::PostgreSQL.config.predicate_builder.handle_array_attributes = true }
    after { Torque::PostgreSQL.config.predicate_builder.handle_array_attributes = false }

    it 'works with plain array when disabled' do
      Torque::PostgreSQL.config.predicate_builder.handle_array_attributes = false

      sql = subject.where(tag_ids: 1).to_sql
      expect(sql).to include("WHERE \"items\".\"tag_ids\" = 1")

      sql = subject.where(tag_ids: [1, 2, 3]).to_sql
      expect(sql).to include("WHERE \"items\".\"tag_ids\" = '{1,2,3}'")
    end

    it 'works with a single value' do
      sql = subject.where(tag_ids: 1).to_sql
      expect(sql).to include("WHERE 1 = ANY(\"items\".\"tag_ids\")")
    end

    it 'works with an array value' do
      sql = subject.where(tag_ids: [1, 2, 3]).to_sql
      expect(sql).to include("WHERE \"items\".\"tag_ids\" && '{1,2,3}'")
    end

    it 'works with an empty array' do
      sql = subject.where(tag_ids: []).to_sql
      expect(sql).to include("WHERE CARDINALITY(\"items\".\"tag_ids\") = 0")
    end

    it 'keeps nil as a null check' do
      sql = subject.where(tag_ids: nil).to_sql
      expect(sql).to include("WHERE \"items\".\"tag_ids\" IS NULL")

      sql = subject.where.not(tag_ids: nil).to_sql
      expect(sql).to include("WHERE \"items\".\"tag_ids\" IS NOT NULL")
    end

    it 'keeps a nil among the values as a null check' do
      sql = subject.where(tag_ids: [1, nil]).to_sql
      expect(sql).to include("WHERE (\"items\".\"tag_ids\" && '{1}' OR \"items\".\"tag_ids\" IS NULL)")
    end

    it 'resolves records to their ids' do
      tag = Tag.create!(name: 'A')

      sql = subject.where(tag_ids: tag).to_sql
      expect(sql).to include("WHERE #{tag.id} = ANY(\"items\".\"tag_ids\")")

      sql = subject.where(tag_ids: [tag]).to_sql
      expect(sql).to include("WHERE \"items\".\"tag_ids\" && '{#{tag.id}}'")
    end

    it 'accepts a set of values' do
      sql = subject.where(tag_ids: Set[1, 2]).to_sql
      expect(sql).to include("WHERE \"items\".\"tag_ids\" && '{1,2}'")
    end

    it 'properly binds the provided values' do
      sql, binds = get_query_with_binds { subject.where(tag_ids: 1).load }
      expect(sql).to include("WHERE $1 = ANY(\"items\".\"tag_ids\")")
      expect(binds.first.value).to eq(1)

      sql, binds = get_query_with_binds { subject.where(tag_ids: [1, 2, 3]).load }
      expect(sql).to include("WHERE \"items\".\"tag_ids\" && $1")
      expect(binds.first.value).to eq([1, 2, 3])

      sql, binds = get_query_with_binds { subject.where(tag_ids: []).load }
      expect(sql).to include("WHERE CARDINALITY(\"items\".\"tag_ids\") = 0")
      expect(binds).to be_empty
    end
  end

  describe 'on regexp' do
    subject { Video.all }

    it 'works with a basic regular expression' do
      sql = subject.where(title: /(a|b)/).to_sql
      expect(sql).to include("WHERE \"videos\".\"title\" ~ '(a|b)'")
    end

    it 'works with a case-insensitive regular expression' do
      sql = subject.where(title: /(a|b)/i).to_sql
      expect(sql).to include("WHERE \"videos\".\"title\" ~* '(a|b)'")
    end

    it 'works with characters that need escape' do
      sql = subject.where(title: %r{a|'|"|\\}).to_sql
      expect(sql).to include("WHERE \"videos\".\"title\" ~ 'a|''|\"|\\\\'")
    end

    it 'properly binds the provided value' do
      query = subject.where(title: /(a|b)/)

      sql, binds = get_query_with_binds { query.load }
      expect(sql).to include("WHERE \"videos\".\"title\" ~ $1")
      expect(binds.first.value).to eq('(a|b)')
    end
  end

  describe 'on normalized attributes' do
    before { Torque::PostgreSQL.config.predicate_builder.handle_array_attributes = true }
    after { Torque::PostgreSQL.config.predicate_builder.handle_array_attributes = false }

    let(:item_klass) do
      Class.new(Item) do
        normalizes :tag_ids, with: ->(value) { value.is_a?(::Array) ? value.uniq : value }
      end
    end

    let(:place_klass) do
      Class.new(Place) do
        normalizes :home, with: ->(value) { value }
        normalizes :offices, with: ->(value) { value }
      end
    end

    let(:profile_klass) do
      Class.new(Profile) do
        normalizes :settings, with: ->(value) { value }
      end
    end

    let(:category_klass) do
      Class.new(Category) do
        normalizes :path, with: ->(value) { value }
        normalizes :patterns, with: ->(value) { value }
      end
    end

    it 'still sees an array column as an array' do
      sql = item_klass.where(tag_ids: 1).to_sql
      expect(sql).to include(%[WHERE 1 = ANY("items"."tag_ids")])

      sql = item_klass.where(tag_ids: [1, 2]).to_sql
      expect(sql).to include(%[WHERE "items"."tag_ids" && '{1,2}'])

      sql = item_klass.where(tag_ids: []).to_sql
      expect(sql).to include(%[WHERE CARDINALITY("items"."tag_ids") = 0])
    end

    it 'applies the normalization to the values of an array condition' do
      sql = item_klass.where(tag_ids: [1, 1, 2]).to_sql
      expect(sql).to include(%[WHERE "items"."tag_ids" && '{1,2}'])
    end

    it 'still sees an array column on either side of an arel attribute' do
      sql = item_klass.where(tag_ids: Item.arel_table[:id]).to_sql
      expect(sql).to include(%[WHERE "items"."id" = ANY("items"."tag_ids")])

      sql = Item.where(id: item_klass.arel_table[:tag_ids]).to_sql
      expect(sql).to include(%[WHERE "items"."id" = ANY("items"."tag_ids")])
    end

    it 'still breaks a hash into conditions over a composite column' do
      sql = place_klass.where(home: { street: 'Main' }).to_sql
      expect(sql).to include(%[(("places"."home")."street" = 'Main')])

      sql = place_klass.where(offices: { street: 'A' }).to_sql
      expect(sql).to include(%[FROM UNNEST("places"."offices") "address"])
    end

    it 'still casts a whole composite value to its type' do
      sql = place_klass.where(home: Composite::Address.new(street: 'Main')).to_sql
      expect(sql).to include(%[WHERE "places"."home" = '("Main",,,)'::address])
    end

    it 'still breaks a hash into conditions over a struct column' do
      sql = profile_klass.where(settings: { theme: 'dark' }).to_sql
      expect(sql).to include(%[("profiles"."settings" #>> ARRAY['theme']) = 'dark'])
    end

    it 'still tells a pattern from a path on an ltree column' do
      sql = category_klass.where(path: ['Top', :any]).to_sql
      expect(sql).to include(%[WHERE "categories"."path" ~ 'Top.*'::lquery])

      sql = category_klass.where(path: %w[Top Science]).to_sql
      expect(sql).to include(%[WHERE "categories"."path" = 'Top.Science'])

      sql = category_klass.where(patterns: 'Top.Science').to_sql
      expect(sql).to include(%[WHERE 'Top.Science'::ltree ~ ANY("categories"."patterns")])
    end

    it 'still resolves the parts of a column on order' do
      sql = place_klass.order(home: { street: :asc }).to_sql
      expect(sql).to include(%[ORDER BY ("places"."home")."street" ASC])

      sql = profile_klass.order(settings: { theme: :asc }).to_sql
      expect(sql).to include(%[ORDER BY ("profiles"."settings" #>> ARRAY['theme']) ASC])
    end
  end
end
