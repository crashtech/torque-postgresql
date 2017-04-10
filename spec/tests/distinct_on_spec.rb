require 'spec_helper'

RSpec.describe 'DistinctOn' do

  context 'on relation' do
    subject { Post.unscoped }

    it 'has its method' do
      expect(subject).to respond_to(:distinct_on)
    end

    it 'doesn\'t mess with original distinct form without select' do
      expect(subject.distinct.to_sql).to \
        eql('SELECT DISTINCT "posts".* FROM "posts"')
    end

    it 'doesn\'t mess with original distinct form with select' do
      expect(subject.select(:name).distinct.to_sql).to \
        eql('SELECT DISTINCT "name" FROM "posts"')
    end

    it 'is able to do the basic form' do
      expect(subject.distinct_on(:title).to_sql).to \
        eql('SELECT DISTINCT ON ( "posts"."title" ) "posts".* FROM "posts"')
    end

    it 'is able to do with multiple attributes' do
      expect(subject.distinct_on(:title, :content).to_sql).to \
        eql('SELECT DISTINCT ON ( "posts"."title", "posts"."content" ) "posts".* FROM "posts"')
    end

    it 'is able to do with relation' do
      expect(subject.distinct_on(author: :name).to_sql).to \
        eql('SELECT DISTINCT ON ( "authors"."name" ) "posts".* FROM "posts"')
    end

    it 'is able to do with relation and multiple attributes' do
      expect(subject.distinct_on(author: [:name, :age]).to_sql).to \
        eql('SELECT DISTINCT ON ( "authors"."name", "authors"."age" ) "posts".* FROM "posts"')
    end

    it 'raises with invalid relation' do
      expect { subject.distinct_on(tags: :name).to_sql }.to \
        raise_error(ArgumentError, /Relation for/)
    end

    it 'raises with third level hash' do
      expect { subject.distinct_on(author: [comments: :body]).to_sql }.to \
        raise_error(ArgumentError, /on third level/)
    end
  end

  context 'on model' do
    subject { Post }

    it 'has its method' do
      expect(subject).to respond_to(:distinct_on)
    end

    it 'returns a relation when using the method' do
      expect(subject.distinct_on(:title)).to be_a(ActiveRecord::Relation)
    end
  end

end
