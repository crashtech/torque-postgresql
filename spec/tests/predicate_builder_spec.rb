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
end
