require 'spec_helper'

RSpec.describe 'BelongsToMany' do
  context 'on model' do
    let(:model) { Video }
    let(:key) { :tests }
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

    it 'allows setting up foreign key and primary_key as symbol' do
      model.belongs_to_many(:tests, foreign_key: :test_ids, primary_key: :test_id)

      reflection = model._reflections[key]
      expect(reflection.foreign_key).to be_eql('test_ids')
      expect(reflection.active_record_primary_key).to be_eql('test_id')
    end
  end

  context 'on association' do
    let(:other) { Tag }
    let(:key) { :tags }
    let(:initial) { FactoryBot.create(:tag) }

    before { Video.belongs_to_many(:tags) }
    subject { Video.create(title: 'A') }

    after do
      Video.reset_callbacks(:save)
      Video._reflections = {}
    end

    it 'has the method' do
      expect(subject).to respond_to(:tags)
      expect(subject._reflections).to include(key)
    end

    it 'has correct foreign key' do
      item = subject._reflections[key]
      expect(item.foreign_key).to be_eql('tag_ids')
    end

    it 'loads associated records' do
      subject.update(tag_ids: [initial.id])
      expect(subject.tags.to_sql).to be_eql(<<-SQL.squish)
        SELECT "tags".* FROM "tags" WHERE "tags"."id" = #{initial.id}
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

    it 'can create the owner record with direct set items' do
      # Having another association would break this test due to how
      # +@new_record_before_save+ is set on autosave association
      Video.has_many(:comments)

      record = Video.create(title: 'A', tags: [initial])
      record.reload

      expect(record.tags.size).to be_eql(1)
      expect(record.tags.first.id).to be_eql(initial.id)
    end

    it 'can keep record changes accordingly' do
      expect(subject.tags.count).to be_eql(0)

      local_previous_changes = nil
      local_saved_changes = nil

      Video.after_commit do
        local_previous_changes = self.previous_changes.dup
        local_saved_changes = self.saved_changes.dup
      end

      subject.update(title: 'B')

      expect(local_previous_changes).to include('title')
      expect(local_saved_changes).to include('title')

      subject.tags = FactoryBot.create_list(:tag, 5)
      subject.update(title: 'C', url: 'X')
      subject.reload

      expect(local_previous_changes).to include('title', 'url')
      expect(local_saved_changes).to include('title', 'url')
      expect(local_previous_changes).not_to include('tag_ids')
      expect(local_saved_changes).not_to include('tag_ids')
      expect(subject.tag_ids.size).to be_eql(5)
      expect(subject.tags.count).to be_eql(5)
    end

    it 'can assign the record ids during before callback' do
      Video.before_save { self.tags = FactoryBot.create_list(:tag, 5) }

      record = Video.create(title: 'A')

      expect(Tag.count).to be_eql(5)
      expect(record.tag_ids.size).to be_eql(5)
      expect(record.tags.count).to be_eql(5)
    end

    it 'does not trigger after commit on the associated record' do
      called = false

      tag = FactoryBot.create(:tag)
      Tag.after_commit { called = true }

      expect(called).to be_falsey

      subject.tags << tag

      expect(subject.tag_ids).to be_eql([tag.id])
      expect(called).to be_falsey

      Tag.reset_callbacks(:commit)
    end

    it 'can build an associated record' do
      record = subject.tags.build(name: 'Test')
      expect(record).to be_a(other)
      expect(record).not_to be_persisted
      expect(record.name).to be_eql('Test')
      expect(subject.tags.target).to be_eql([record])

      expect(subject.save && subject.reload).to be_truthy
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
      subject.reload

      expect(subject.tags.size).to be_eql(2)
      expect(subject.tag_ids.size).to be_eql(2)
      expect(subject.tags.last.name).to be_eql('Test')
    end

    it 'can replace records' do
      subject.tags << FactoryBot.create(:tag)
      expect(subject.tags.size).to be_eql(1)

      subject.tags = [other.new(name: 'Test 1')]
      subject.reload

      expect(subject.tags.size).to be_eql(1)
      expect(subject.tags[0].name).to be_eql('Test 1')

      subject.tags.replace([other.new(name: 'Test 2'), other.new(name: 'Test 3')])
      subject.reload

      expect(subject.tags.size).to be_eql(2)
      expect(subject.tags[0].name).to be_eql('Test 2')
      expect(subject.tags[1].name).to be_eql('Test 3')
    end

    it 'can delete specific records' do
      subject.tags << initial
      expect(subject.tags.size).to be_eql(1)

      subject.tags.delete(initial)
      expect(subject.tags.size).to be_eql(0)
      expect(subject.reload.tags.size).to be_eql(0)
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

    it 'can clear the array' do
      record = Video.create(title: 'B', tags: [initial])
      expect(record.tags.size).to be_eql(1)

      record.update(tag_ids: [])
      record.reload

      expect(record.tag_ids).to be_nil
      expect(record.tags.size).to be_eql(0)
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

      expect(subject.tags).not_to be_include(inside)
      expect(subject.tags).not_to be_include(outside)

      subject.tags << inside

      expect(subject.tags).to respond_to(:include?)
      expect(subject.tags).to be_include(inside)
      expect(subject.tags).not_to be_include(outside)
    end

    it 'can append records' do
      subject.tags << other.new(name: 'Test 1')
      expect(subject.tags.size).to be_eql(1)

      subject.tags << other.new(name: 'Test 2')
      subject.update(title: 'B')
      subject.reload

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
      new_tag = FactoryBot.create(:tag)
      subject.tags << new_tag

      subject.tags.reload
      expect(subject.tags.size).to be_eql(1)
      expect(subject.tags.first.id).to be_eql(new_tag.id)

      record = Video.create(title: 'B', tags: [new_tag])
      record.reload

      expect(record.tags.size).to be_eql(1)
      expect(record.tags.first.id).to be_eql(new_tag.id)
    end

    it 'can preload records' do
      records = FactoryBot.create_list(:tag, 5)
      subject.tags.concat(records)

      entries = Video.all.includes(:tags).load

      expect(entries.size).to be_eql(1)
      expect(entries.first.tags).to be_loaded
      expect(entries.first.tags.size).to be_eql(5)
    end

    it 'can preload records using ActiveRecord::Associations::Preloader' do
      records = FactoryBot.create_list(:tag, 5)
      subject.tags.concat(records)

      entries = Video.all
      arguments = { records: entries, associations: :tags, available_records: Tag.all.to_a }
      ActiveRecord::Associations::Preloader.new(**arguments).call
      entries = entries.load

      expect(entries.size).to be_eql(1)
      expect(entries.first.tags).to be_loaded
      expect(entries.first.tags.size).to be_eql(5)
    end

    it 'can joins records' do
      query = Video.all.joins(:tags)
      expect(query.to_sql).to match(/INNER JOIN "tags"/)
      expect { query.load }.not_to raise_error
    end

    context 'when handling binds' do
      let(:tag_ids) { FactoryBot.create_list(:tag, 5).map(&:id) }
      let!(:record) { Video.new(tag_ids: tag_ids) }

      it 'uses rails default with in and several binds' do
        sql, binds = get_query_with_binds { record.tags.load }

        expect(sql).to include(' WHERE "tags"."id" IN ($1, $2, $3, $4, $5)')
        expect(binds.size).to be_eql(5)
      end
    end

    context 'when the attribute has a default value' do
      subject { FactoryBot.create(:item) }

      it 'will always return the column default value' do
        expect(subject.tag_ids).to be_a(Array)
        expect(subject.tag_ids).to be_eql([1])
      end

      it 'will keep the value as an array even when the association is cleared' do
        records = FactoryBot.create_list(:tag, 5)
        subject.tags.concat(records)

        subject.reload
        expect(subject.tag_ids).to be_a(Array)
        expect(subject.tag_ids).not_to be_eql([1, *records.map(&:id)])

        subject.tags.clear
        subject.reload
        expect(subject.tag_ids).to be_a(Array)
        expect(subject.tag_ids).to be_eql([1])
      end
    end

    context 'when record is not persisted' do
      let(:initial) { FactoryBot.create(:tag) }

      subject { Video.new(title: 'A', tags: [initial]) }

      it 'loads associated records' do
        expect(subject.tags.load).to be_a(ActiveRecord::Associations::CollectionProxy)
        expect(subject.tags.to_a).to be_eql([initial])
      end
    end
  end

  context 'using uuid' do
    let(:connection) { ActiveRecord::Base.connection }
    let(:game) { Class.new(ActiveRecord::Base) }
    let(:player) { Class.new(ActiveRecord::Base) }
    let(:other) { player.create }

    # TODO: Set as a shared example
    before do
      connection.create_table(:players, id: :uuid) { |t| t.string :name }
      connection.create_table(:games, id: :uuid) { |t| t.uuid :player_ids, array: true }

      game.table_name = 'games'
      player.table_name = 'players'
      game.belongs_to_many :players, anonymous_class: player,
        inverse_of: false, foreign_key: :player_ids
    end

    subject { game.create }

    it 'loads one associated records' do
      subject.update(player_ids: [other.id])
      expect(subject.players.to_sql).to be_eql(<<-SQL.squish)
        SELECT "players".* FROM "players" WHERE "players"."id" = '#{other.id}'
      SQL

      expect(subject.players.load).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(subject.players.to_a).to be_eql([other])
    end

    it 'loads several associated records' do
      entries = [other, player.create]
      subject.update(player_ids: entries.map(&:id))
      expect(subject.players.to_sql).to be_eql(<<-SQL.squish)
        SELECT "players".* FROM "players"
        WHERE "players"."id" IN ('#{entries[0].id}', '#{entries[1].id}')
      SQL

      expect(subject.players.load).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(subject.players.to_a).to be_eql(entries)
    end

    it 'can preload records' do
      records = 5.times.map { player.create }
      subject.players.concat(records)

      entries = game.all.includes(:players).load

      expect(entries.size).to be_eql(1)
      expect(entries.first.players).to be_loaded
      expect(entries.first.players.size).to be_eql(5)
    end

    it 'can joins records' do
      query = game.all.joins(:players)
      expect(query.to_sql).to match(/INNER JOIN "players"/)
      expect { query.load }.not_to raise_error
    end
  end

  context 'using callbacks' do
    let(:tags) { FactoryBot.create_list(:tag, 3) }
    let(:collectors) { Hash.new { |h, k| h[k] = [] } }

    subject { Video.create(title: 'A') }

    after do
      Video.reset_callbacks(:save)
      Video._reflections = {}
    end

    before do
      subject.update_attribute(:tag_ids, tags.first(2).pluck(:id))
      Video.belongs_to_many(:tags,
        before_add:    ->(_, tag) { collectors[:before_add]    << tag },
        after_add:     ->(_, tag) { collectors[:after_add]     << tag },
        before_remove: ->(_, tag) { collectors[:before_remove] << tag },
        after_remove:  ->(_, tag) { collectors[:after_remove]  << tag },
      )
    end

    it 'works with id changes' do
      subject.tag_ids = tags.drop(1).pluck(:id)
      subject.save!

      expect(collectors[:before_add]).to be_eql([tags.last])
      expect(collectors[:after_add]).to be_eql([tags.last])

      expect(collectors[:before_remove]).to be_eql([tags.first])
      expect(collectors[:after_remove]).to be_eql([tags.first])
    end

    it 'works with record changes' do
      subject.tags = tags.drop(1)

      expect(collectors[:before_add]).to be_eql([tags.last])
      expect(collectors[:after_add]).to be_eql([tags.last])

      expect(collectors[:before_remove]).to be_eql([tags.first])
      expect(collectors[:after_remove]).to be_eql([tags.first])
    end
  end

  context 'using custom keys' do
    let(:connection) { ActiveRecord::Base.connection }
    let(:post) { Post }
    let(:tag) { Tag }
    let(:tags) { %w[a b c].map { |id| create(:tag, friendly_id: id) } }

    subject { create(:post) }

    before do
      connection.add_column(:tags, :friendly_id, :string)
      connection.add_column(:posts, :friendly_tag_ids, :string, array: true)
      post.belongs_to_many(:tags, foreign_key: :friendly_tag_ids, primary_key: :friendly_id)
      post.reset_column_information
      tag.reset_column_information
    end

    after do
      tag.reset_column_information
      post.reset_column_information
      post._reflections.delete(:tags)
    end

    it 'loads associated records' do
      subject.update(friendly_tag_ids: tags.pluck(:friendly_id))

      expect(subject.tags.to_sql).to be_eql(<<-SQL.squish)
        SELECT "tags".* FROM "tags" WHERE "tags"."friendly_id" IN ('a', 'b', 'c')
      SQL

      expect(subject.tags.load).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(subject.tags.to_a).to be_eql(tags)
    end

    it 'can properly assign tags' do
      expect(subject.friendly_tag_ids).to be_blank

      subject.tags = tags
      expect(subject.friendly_tag_ids).to be_eql(%w[a b c])
    end
  end
end
