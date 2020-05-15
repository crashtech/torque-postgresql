require 'spec_helper'

RSpec.describe 'HasMany' do
  context 'on builder' do
    let(:builder) { ActiveRecord::Associations::Builder::HasMany }

    it 'adds the array option' do
      expect(builder.send(:valid_options, [])).to include(:array)
    end
  end

  context 'on original' do
    let(:other) { Text }

    before { User.has_many :texts }
    subject { User.create(name: 'User 1') }
    after { User._reflections = {} }

    it 'has the method' do
      expect(subject).to respond_to(:texts)
      expect(subject._reflections).to include('texts')
    end

    it 'loads associated records' do
      expect(subject.texts.to_sql).to match(Regexp.new(<<-SQL.squish))
        SELECT "texts"\\.\\* FROM "texts" WHERE \\(?"texts"\\."user_id" = #{subject.id}\\)?
      SQL

      expect(subject.texts.load).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(subject.texts.to_a).to be_eql([])
    end

    it 'can be marked as loaded' do
      expect(subject.texts.loaded?).to be_eql(false)
      expect(subject.texts).to respond_to(:load_target)
      expect(subject.texts.load_target).to be_eql([])
      expect(subject.texts.loaded?).to be_eql(true)
    end

    it 'can find specific records' do
      records = FactoryBot.create_list(:text, 10, user_id: subject.id)
      ids = records.map(&:id).sample(5)

      expect(subject.texts).to respond_to(:find)
      records = subject.texts.find(*ids)

      expect(records.size).to be_eql(5)
      expect(records.map(&:id).sort).to be_eql(ids.sort)
    end

    it 'can return last n records' do
      records = FactoryBot.create_list(:text, 10, user_id: subject.id)
      ids = records.map(&:id).last(5)

      expect(subject.texts).to respond_to(:last)
      records = subject.texts.last(5)

      expect(records.size).to be_eql(5)
      expect(records.map(&:id).sort).to be_eql(ids.sort)
    end

    it 'can return first n records' do
      records = FactoryBot.create_list(:text, 10, user_id: subject.id)
      ids = records.map(&:id).first(5)

      expect(subject.texts).to respond_to(:take)
      records = subject.texts.take(5)

      expect(records.size).to be_eql(5)
      expect(records.map(&:id).sort).to be_eql(ids.sort)
    end

    it 'can build an associated record' do
      record = subject.texts.build(content: 'Test')
      expect(record).to be_a(other)
      expect(record).not_to be_persisted
      expect(record.content).to be_eql('Test')
      expect(record.user_id).to be_eql(subject.id)

      expect(subject.save).to be_truthy
      expect(subject.texts.size).to be_eql(1)
    end

    it 'can create an associated record' do
      record = subject.texts.create(content: 'Test')
      expect(subject.texts).to respond_to(:create!)

      expect(record).to be_a(other)
      expect(record).to be_persisted
      expect(record.content).to be_eql('Test')
      expect(record.user_id).to be_eql(subject.id)
    end

    it 'can concat records' do
      FactoryBot.create(:text, user_id: subject.id)
      expect(subject.texts.size).to be_eql(1)

      subject.texts.concat(other.new(content: 'Test'))
      expect(subject.texts.size).to be_eql(2)
      expect(subject.texts.last.content).to be_eql('Test')
    end

    it 'can replace records' do
      FactoryBot.create(:text, user_id: subject.id)
      expect(subject.texts.size).to be_eql(1)

      subject.texts.replace([other.new(content: 'Test 1'), other.new(content: 'Test 2')])
      expect(subject.texts.size).to be_eql(2)
      expect(subject.texts[0].content).to be_eql('Test 1')
      expect(subject.texts[1].content).to be_eql('Test 2')
    end

    it 'can delete all records' do
      FactoryBot.create_list(:text, 5, user_id: subject.id)
      expect(subject.texts.size).to be_eql(5)

      subject.texts.delete_all
      expect(subject.texts.size).to be_eql(0)
    end

    it 'can destroy all records' do
      FactoryBot.create_list(:text, 5, user_id: subject.id)
      expect(subject.texts.size).to be_eql(5)

      subject.texts.destroy_all
      expect(subject.texts.size).to be_eql(0)
    end

    it 'can have sum operations' do
      result = FactoryBot.create_list(:text, 5, user_id: subject.id).map(&:id).reduce(:+)
      expect(subject.texts).to respond_to(:sum)
      expect(subject.texts.sum(:id)).to be_eql(result)
    end

    it 'can have a pluck operation' do
      result = FactoryBot.create_list(:text, 5, user_id: subject.id).map(&:content).sort
      expect(subject.texts).to respond_to(:pluck)
      expect(subject.texts.pluck(:content).sort).to be_eql(result)
    end

    it 'can be markes as empty' do
      expect(subject.texts).to respond_to(:empty?)
      expect(subject.texts.empty?).to be_truthy

      FactoryBot.create(:text, user_id: subject.id)
      expect(subject.texts.empty?).to be_falsey
    end

    it 'can check if a record is included on the list' do
      inside = FactoryBot.create(:text, user_id: subject.id)
      outside = FactoryBot.create(:text)

      expect(subject.texts).to respond_to(:include?)
      expect(subject.texts.include?(inside)).to be_truthy
      expect(subject.texts.include?(outside)).to be_falsey
    end

    it 'can append records' do
      FactoryBot.create(:text, user_id: subject.id)
      expect(subject.texts.size).to be_eql(1)

      subject.texts << other.new(content: 'Test')
      expect(subject.texts.size).to be_eql(2)
      expect(subject.texts.last.content).to be_eql('Test')
    end

    it 'can clear records' do
      FactoryBot.create(:text, user_id: subject.id)
      expect(subject.texts.size).to be_eql(1)

      subject.texts.clear
      expect(subject.texts.size).to be_eql(0)
    end

    it 'can reload records' do
      expect(subject.texts.size).to be_eql(0)
      FactoryBot.create(:text, user_id: subject.id)

      expect(subject.texts.size).to be_eql(0)

      subject.texts.reload
      expect(subject.texts.size).to be_eql(1)
    end

    it 'can preload records' do
      FactoryBot.create_list(:text, 5, user_id: subject.id)
      entries = User.all.includes(:texts).load

      expect(entries.size).to be_eql(1)
      expect(entries.first.texts).to be_loaded
      expect(entries.first.texts.size).to be_eql(5)
    end

    it 'can joins records' do
      query = User.all.joins(:texts)
      expect(query.to_sql).to match(/INNER JOIN "texts"/)
      expect { query.load }.not_to raise_error
    end
  end

  context 'on array' do
    let(:other) { Video }

    before { Tag.has_many :videos, array: true }
    subject { Tag.create(name: 'A') }
    after { Tag._reflections = {} }

    it 'has the method' do
      expect(subject).to respond_to(:videos)
      expect(subject._reflections).to include('videos')
    end

    it 'loads associated records' do
      expect(subject.videos.to_sql).to match(Regexp.new(<<-SQL.squish))
        SELECT "videos"\\.\\* FROM "videos"
        WHERE \\(?"videos"\\."tag_ids" && ARRAY\\[#{subject.id}\\]::bigint\\[\\]\\)?
      SQL

      expect(subject.videos.load).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(subject.videos.to_a).to be_eql([])
    end

    it 'can be marked as loaded' do
      expect(subject.videos.loaded?).to be_eql(false)
      expect(subject.videos).to respond_to(:load_target)
      expect(subject.videos.load_target).to be_eql([])
      expect(subject.videos.loaded?).to be_eql(true)
    end

    it 'can find specific records' do
      records = FactoryBot.create_list(:video, 10, tag_ids: [subject.id])
      ids = records.map(&:id).sample(5)

      expect(subject.videos).to respond_to(:find)
      records = subject.videos.find(*ids)

      expect(records.size).to be_eql(5)
      expect(records.map(&:id).sort).to be_eql(ids.sort)
    end

    it 'can return last n records' do
      records = FactoryBot.create_list(:video, 10, tag_ids: [subject.id])
      ids = records.map(&:id).last(5)

      expect(subject.videos).to respond_to(:last)
      records = subject.videos.last(5)

      expect(records.size).to be_eql(5)
      expect(records.map(&:id).sort).to be_eql(ids.sort)
    end

    it 'can return first n records' do
      records = FactoryBot.create_list(:video, 10, tag_ids: [subject.id])
      ids = records.map(&:id).first(5)

      expect(subject.videos).to respond_to(:take)
      records = subject.videos.take(5)

      expect(records.size).to be_eql(5)
      expect(records.map(&:id).sort).to be_eql(ids.sort)
    end

    it 'can build an associated record' do
      record = subject.videos.build(title: 'Test')
      expect(record).to be_a(other)
      expect(record).not_to be_persisted
      expect(record.title).to be_eql('Test')

      expect(subject.save).to be_truthy
      expect(record.tag_ids).to be_eql([subject.id])
      expect(subject.videos.size).to be_eql(1)
    end

    it 'can create an associated record' do
      record = subject.videos.create(title: 'Test')
      expect(subject.videos).to respond_to(:create!)

      expect(record).to be_a(other)
      expect(record).to be_persisted
      expect(record.title).to be_eql('Test')
      expect(record.tag_ids).to be_eql([subject.id])
    end

    it 'can concat records' do
      FactoryBot.create(:video, tag_ids: [subject.id])
      expect(subject.videos.size).to be_eql(1)

      subject.videos.concat(other.new(title: 'Test'))
      expect(subject.videos.size).to be_eql(2)
      expect(subject.videos.last.title).to be_eql('Test')
    end

    it 'can replace records' do
      FactoryBot.create(:video, tag_ids: [subject.id])
      expect(subject.videos.size).to be_eql(1)

      subject.videos.replace([other.new(title: 'Test 1'), other.new(title: 'Test 2')])
      expect(subject.videos.size).to be_eql(2)
      expect(subject.videos[0].title).to be_eql('Test 1')
      expect(subject.videos[1].title).to be_eql('Test 2')
    end

    it 'can delete all records' do
      FactoryBot.create_list(:video, 5, tag_ids: [subject.id])
      expect(subject.videos.size).to be_eql(5)

      subject.videos.delete_all
      expect(subject.videos.size).to be_eql(0)
    end

    it 'can destroy all records' do
      FactoryBot.create_list(:video, 5, tag_ids: [subject.id])
      expect(subject.videos.size).to be_eql(5)

      subject.videos.destroy_all
      expect(subject.videos.size).to be_eql(0)
    end

    it 'can have sum operations' do
      result = FactoryBot.create_list(:video, 5, tag_ids: [subject.id]).map(&:id).reduce(:+)
      expect(subject.videos).to respond_to(:sum)
      expect(subject.videos.sum(:id)).to be_eql(result)
    end

    it 'can have a pluck operation' do
      result = FactoryBot.create_list(:video, 5, tag_ids: [subject.id]).map(&:title).sort
      expect(subject.videos).to respond_to(:pluck)
      expect(subject.videos.pluck(:title).sort).to be_eql(result)
    end

    it 'can be markes as empty' do
      expect(subject.videos).to respond_to(:empty?)
      expect(subject.videos.empty?).to be_truthy

      FactoryBot.create(:video, tag_ids: [subject.id])
      expect(subject.videos.empty?).to be_falsey
    end

    it 'can check if a record is included on the list' do
      inside = FactoryBot.create(:video, tag_ids: [subject.id])
      outside = FactoryBot.create(:video)

      expect(subject.videos).to respond_to(:include?)
      expect(subject.videos.include?(inside)).to be_truthy
      expect(subject.videos.include?(outside)).to be_falsey
    end

    it 'can append records' do
      FactoryBot.create(:video, tag_ids: [subject.id])
      expect(subject.videos.size).to be_eql(1)

      subject.videos << other.new(title: 'Test')
      expect(subject.videos.size).to be_eql(2)
      expect(subject.videos.last.title).to be_eql('Test')
    end

    it 'can clear records' do
      FactoryBot.create(:video, tag_ids: [subject.id])
      expect(subject.videos.size).to be_eql(1)

      subject.videos.clear
      expect(subject.videos.size).to be_eql(0)
    end

    it 'can reload records' do
      expect(subject.videos.size).to be_eql(0)
      FactoryBot.create(:video, tag_ids: [subject.id])

      expect(subject.videos.size).to be_eql(0)

      subject.videos.reload
      expect(subject.videos.size).to be_eql(1)
    end

    it 'can preload records' do
      FactoryBot.create_list(:video, 5, tag_ids: [subject.id])
      entries = Tag.all.includes(:videos).load

      expect(entries.size).to be_eql(1)
      expect(entries.first.videos).to be_loaded
      expect(entries.first.videos.size).to be_eql(5)
    end

    it 'can joins records' do
      query = Tag.all.joins(:videos)
      expect(query.to_sql).to match(/INNER JOIN "videos"/)
      expect { query.load }.not_to raise_error
    end
  end
end
