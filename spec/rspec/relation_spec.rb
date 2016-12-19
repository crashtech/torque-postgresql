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
      check = [:title, authors: :name]
      result = [['posts', 'title'], ['authors', 'name']]
      expect(subject.call(check)).to be_attributes_as(result)
    end

    it 'asserts multiple values on hash definition' do
      check = [authors: [:name, :age]]
      result = [['authors', 'name'], ['authors', 'age']]
      expect(subject.call(check)).to be_attributes_as(result)
    end

    it 'raises on relation not present' do
      check = [tags: :name]
      expect{ subject.call(check) }.to raise_error(ArgumentError, /Relation for/)
    end

    it 'raises on third level access' do
      check = [authors: [comments: :body]]
      expect{ subject.call(check) }.to raise_error(ArgumentError, /on third level/)
    end
  end

end
