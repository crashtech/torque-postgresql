require 'spec_helper'

RSpec.describe 'Function' do
  let(:helper) { Torque::PostgreSQL::FN }
  let(:conn) { ActiveRecord::Base.connection }
  let(:visitor) { ::Arel::Visitors::PostgreSQL.new(conn) }
  let(:collector) { ::Arel::Collectors::SQLString }

  context 'on helper' do
    it 'helps creating a bind' do
      type = ::ActiveRecord::Type::String.new
      expect(helper.bind(:foo, 'test', type)).to be_a(::Arel::Nodes::BindParam)
    end

    it 'helps creating a bind for a model attribute' do
      expect(helper.bind_for(Video, :title, 'test')).to be_a(::Arel::Nodes::BindParam)
    end

    it 'helps creating a bind for an arel attribute' do
      attr = Video.arel_table['title']
      expect(helper.bind_with(attr, 'test')).to be_a(::Arel::Nodes::BindParam)
    end

    it 'helps concatenating arguments' do
      values = %w[a b c].map(&::Arel.method(:sql))

      # Unable to just call .sql with a simple thing
      visited = visitor.accept(helper.concat(values[0]), collector.new)
      expect(visited.value).to eq("a")

      # 2+ we can call .sql directly
      expect(helper.concat(values[0], values[1]).to_sql).to eq("a || b")
      expect(helper.concat(values[0], values[1], values[2]).to_sql).to eq("a || b || c")
    end

    it 'helps building any other function' do
      values = %w[a b c].map(&::Arel.method(:sql))
      expect(helper).to respond_to(:coalesce)
      expect(helper.coalesce(values[0], values[1]).to_sql).to eq("COALESCE(a, b)")
    end
  end
end
