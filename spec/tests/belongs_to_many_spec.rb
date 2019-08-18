require 'spec_helper'

RSpec.describe 'BelongsToMany' do
  context 'on model' do
    let(:model) { Video }
    let(:builder) { Torque::PostgreSQL::Associations::Builder::BelongsToMany }
    let(:reflection) { Torque::PostgreSQL::Reflection::BelongsToManyReflection }
    after { model._reflections = {} }

    it 'has the builder method' do
      expect(model).to respond_to(:belongs_to_many)
    end

    it 'triggers the correct builder and relation' do
      expect(builder).to receive(:build).with(anything, :tests, nil, {}) do |_, name, _, _|
        ActiveRecord::Reflection.create(:belongs_to_many, name, nil, {}, model)
      end

      expect(reflection).to receive(:new).with(:tests, nil, {}, model)

      model.belongs_to_many(:tests)
    end
  end

  context 'on association' do
    let(:other) { Tag }
    let(:initial) { FactoryBot.create(:tag) }

    before { Video.belongs_to_many :tags }
    subject { Video.create(title: 'A') }
    after { Video._reflections = {} }

    it 'has the method' do
      expect(subject).to respond_to(:tags)
      expect(subject._reflections).to include('tags')
    end

    it 'loads associated records' do
      subject.update(tag_ids: [initial.id])
      expect(subject.tags.to_sql).to match(Regexp.new(<<-SQL.squish))
        SELECT "tags"\\.\\* FROM "tags"
        WHERE \\(?"tags"\\."id" IN \\(#{initial.id}\\)\\)?
      SQL

      expect(subject.tags.load).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(subject.tags.to_a).to be_eql([initial])
    end

    it 'can be marked as loaded' do
      expect(subject.tags.loaded?).to be_eql(false)
      expect(subject.tags).to respond_to(:load_target)
      expect(subject.tags.load_target).to be_eql([])
      expect(subject.tags.loaded?).to be_eql(true)
    end

    it 'can find specific records' do
      records = FactoryBot.create_list(:tag, 10)
      subject.update(tag_ids: records.map(&:id))
      ids = records.map(&:id).sample(5)

      expect(subject.tags).to respond_to(:find)
      records = subject.tags.find(*ids)

      expect(records.size).to be_eql(5)
      expect(records.map(&:id).sort).to be_eql(ids.sort)
    end

    it 'can return last n records' do
      records = FactoryBot.create_list(:tag, 10)
      subject.update(tag_ids: records.map(&:id))
      ids = records.map(&:id).last(5)

      expect(subject.tags).to respond_to(:last)
      records = subject.tags.last(5)

      expect(records.size).to be_eql(5)
      expect(records.map(&:id).sort).to be_eql(ids.sort)
    end

    it 'can return first n records' do
      records = FactoryBot.create_list(:tag, 10)
      subject.update(tag_ids: records.map(&:id))
      ids = records.map(&:id).first(5)

      expect(subject.tags).to respond_to(:take)
      records = subject.tags.take(5)

      expect(records.size).to be_eql(5)
      expect(records.map(&:id).sort).to be_eql(ids.sort)
    end

    it 'can build an associated record' do
      record = subject.tags.build(name: 'Test')
      expect(record).to be_a(other)
      expect(record).not_to be_persisted
      expect(record.name).to be_eql('Test')

      expect(subject.save).to be_truthy
      expect(subject.tag_ids).to be_eql([record.id])
      expect(subject.tags.size).to be_eql(1)
    end

    it 'can create an associated record' do
      record = subject.tags.create(name: 'Test')
      expect(subject.tags).to respond_to(:create!)

      expect(record).to be_a(other)
      expect(record).to be_persisted
      expect(record.name).to be_eql('Test')
      expect(subject.tag_ids).to be_eql([record.id])
    end

    it 'can concat records' do
      record = FactoryBot.create(:tag)
      subject.update(tag_ids: [record.id])
      expect(subject.tags.size).to be_eql(1)

      subject.tags.concat(other.new(name: 'Test'))
      subject.tags.reload
      expect(subject.tags.size).to be_eql(2)
      expect(subject.tag_ids.size).to be_eql(2)
      expect(subject.tags.last.name).to be_eql('Test')
    end

    it 'can replace records' do
      subject.tags << FactoryBot.create(:tag)
      expect(subject.tags.size).to be_eql(1)

      subject.tags.replace([other.new(name: 'Test 1'), other.new(name: 'Test 2')])
      expect(subject.tags.size).to be_eql(2)
      expect(subject.tags[0].name).to be_eql('Test 1')
      expect(subject.tags[1].name).to be_eql('Test 2')
    end

    it 'can delete all records' do
      subject.tags.concat(FactoryBot.create_list(:tag, 5))
      expect(subject.tags.size).to be_eql(5)

      subject.tags.delete_all
      expect(subject.tags.size).to be_eql(0)
    end

    it 'can destroy all records' do
      subject.tags.concat(FactoryBot.create_list(:tag, 5))
      expect(subject.tags.size).to be_eql(5)

      subject.tags.destroy_all
      expect(subject.tags.size).to be_eql(0)
    end

    it 'can have sum operations' do
      records = FactoryBot.create_list(:tag, 5)
      subject.tags.concat(records)

      result = records.map(&:id).reduce(:+)
      expect(subject.tags).to respond_to(:sum)
      expect(subject.tags.sum(:id)).to be_eql(result)
    end

    it 'can have a pluck operation' do
      records = FactoryBot.create_list(:tag, 5)
      subject.tags.concat(records)

      result = records.map(&:name).sort
      expect(subject.tags).to respond_to(:pluck)
      expect(subject.tags.pluck(:name).sort).to be_eql(result)
    end

    it 'can be markes as empty' do
      expect(subject.tags).to respond_to(:empty?)
      expect(subject.tags.empty?).to be_truthy

      subject.tags << FactoryBot.create(:tag)
      expect(subject.tags.empty?).to be_falsey
    end

    it 'can check if a record is included on the list' do
      outside = FactoryBot.create(:tag)
      inside = FactoryBot.create(:tag)
      subject.tags << inside

      expect(subject.tags).to respond_to(:include?)
      expect(subject.tags.include?(inside)).to be_truthy
      expect(subject.tags.include?(outside)).to be_falsey
    end

    it 'can append records' do
      subject.tags << other.new(name: 'Test 1')
      expect(subject.tags.size).to be_eql(1)

      subject.tags << other.new(name: 'Test 2')
      expect(subject.tags.size).to be_eql(2)
      expect(subject.tags.last.name).to be_eql('Test 2')
    end

    it 'can clear records' do
      subject.tags << FactoryBot.create(:tag)
      expect(subject.tags.size).to be_eql(1)

      subject.tags.clear
      expect(subject.tags.size).to be_eql(0)
    end

    it 'can reload records' do
      expect(subject.tags.size).to be_eql(0)
      subject.tags << FactoryBot.create(:tag)

      subject.tags.reload
      expect(subject.tags.size).to be_eql(1)
    end

    it 'can preload records' do
      records = FactoryBot.create_list(:tag, 5)
      subject.tags.concat(records)

      entries = Video.all.includes(:tags).load

      expect(entries.size).to be_eql(1)
      expect(entries.first.tags).to be_loaded
      expect(entries.first.tags.size).to be_eql(5)
    end

    it 'can joins records' do
      query = Video.all.joins(:tags)
      expect(query.to_sql).to match(/INNER JOIN "tags"/)
      expect { query.load }.not_to raise_error
    end
  end
end
