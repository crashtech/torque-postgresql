require 'spec_helper'

RSpec.describe 'Quoting', type: :helper do
  let(:connection) { ActiveRecord::Base.connection }

  context 'on type names' do
    it 'accepts type name only' do
      expect(connection.quote_type_name('sample')).to eql('"public"."sample"')
    end

    it 'accepts schema and type name' do
      expect(connection.quote_type_name('other.sample')).to eql('"other"."sample"')
    end

    it 'accepts schema as a parameter' do
      expect(connection.quote_type_name('sample', 'test')).to eql('"test"."sample"')
    end

    it 'always prefer the schema from parameter' do
      expect(connection.quote_type_name('nothis.sample', 'this')).to eql('"this"."sample"')
    end
  end

end
