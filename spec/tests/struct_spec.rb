require 'spec_helper'

RSpec.describe 'Struct' do
  let(:connection) { ActiveRecord::Base.connection }
  let(:settings_klass) { Profile::Settings }

  context 'on setup' do
    it 'exposes the base method on models' do
      expect(ActiveRecord::Base).to respond_to(:struct_for)
    end

    it 'accepts a configurable method name' do
      expect(Torque::PostgreSQL.config.struct.base_method).to be_eql(:struct_for)
    end

    it 'raises when the column is encrypted on the model level' do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = 'profiles'
          encrypts :settings
          struct_for :settings, Profile::Settings
        end
      end.to raise_error(ArgumentError, /encrypted/)
    end

    it 'raises when the column cannot hold a document' do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = 'profiles'
          struct_for :name, Profile::Bio
        end
      end.to raise_error(ArgumentError, /document/)
    end

    it 'supports any ActiveModel class with attributes' do
      plain_klass = Class.new do
        include ActiveModel::Model
        include ActiveModel::Attributes

        attribute :value, :integer
      end

      model = Class.new(ActiveRecord::Base) do
        self.table_name = 'profiles'
        struct_for :settings, plain_klass
      end

      instance = model.new(settings: { value: '10' })
      expect(instance.settings).to be_a(plain_klass)
      expect(instance.settings.value).to be_eql(10)
    end
  end

  context 'on column types' do
    subject { Profile.new }

    it 'keeps the jsonb type of the column' do
      expect(Profile.type_for_attribute(:settings).type).to be_eql(:jsonb)
    end

    it 'keeps the json type of the column' do
      expect(Profile.type_for_attribute(:bio).type).to be_eql(:json)
    end

    it 'round-trips a json column' do
      subject.bio.headline = 'hello'
      subject.save!

      raw = connection.select_value("SELECT bio::text FROM profiles WHERE id = #{subject.id}")
      expect(raw).to be_present
      expect(subject.reload.bio.headline).to be_eql('hello')
    end
  end

  context 'on casting' do
    subject { Profile.new }

    it 'returns an instance when the column is null' do
      expect(subject.settings).to be_a(settings_klass)
      expect(subject.settings.theme).to be_eql('light')
      expect(subject.settings.notifications).to be_eql(true)
    end

    it 'accepts a hash' do
      subject.settings = { theme: 'dark' }
      expect(subject.settings).to be_a(settings_klass)
      expect(subject.settings.theme).to be_eql('dark')
    end

    it 'accepts an instance' do
      subject.settings = settings_klass.new(theme: 'dark')
      expect(subject.settings.theme).to be_eql('dark')
    end

    it 'accepts nil' do
      subject.settings = nil
      expect(subject.settings).to be_nil
    end

    it 'accepts an instance loaded from another record' do
      origin = Profile.create!(settings: { theme: 'dark' }).reload
      subject.settings = origin.settings
      subject.save!
      expect(subject.reload.settings.theme).to be_eql('dark')
    end

    it 'casts attribute values through their types' do
      subject.settings = { notifications: '0' }
      expect(subject.settings.notifications).to be_eql(false)
    end
  end

  context 'on documents' do
    subject { Profile.create!(name: 'a') }

    let(:document) do
      raw = connection.select_value("SELECT settings::text FROM profiles WHERE id = #{subject.id}")
      ActiveSupport::JSON.decode(raw)
    end

    it 'stores the properties that have a default' do
      expect(document).to be_eql('theme' => 'light', 'notifications' => true)
    end

    it 'marks a new record as changed because of the defaults' do
      expect(Profile.new.changed).to include('settings')
    end

    it 'does not store properties that have no default' do
      expect(document).not_to have_key('tags')
    end

    it 'adds properties as they are written' do
      subject.settings.tags = %w[a]
      subject.save!
      expect(document).to have_key('tags')
    end

    it 'does not add properties that are missing from the document' do
      connection.execute(<<~SQL)
        UPDATE profiles SET settings = '{"tags": ["a"]}' WHERE id = #{subject.id}
      SQL

      subject.reload
      expect(subject.settings.theme).to be_nil
      expect(subject.changed?).to be_falsey

      subject.settings.tags << 'b'
      subject.save!
      expect(document).to be_eql('tags' => %w[a b])
    end
  end

  context 'on defaults' do
    let(:model) do
      options = default_options
      Class.new(ActiveRecord::Base) do
        self.table_name = 'profiles'

        struct_for :settings, Profile::Settings, default: options

        def default_settings
          { theme: 'dark', tags: [name].compact }
        end
      end
    end

    context 'with a hash' do
      let(:default_options) { { theme: 'dark' } }

      it 'overrides the class defaults' do
        expect(model.new.settings.theme).to be_eql('dark')
        expect(model.new.settings.notifications).to be_eql(true)
      end

      it 'saves the defaults and marks the record as changed' do
        record = model.new
        expect(record.changed).to include('settings')

        record.save!
        raw = connection.select_value("SELECT settings::text FROM profiles WHERE id = #{record.id}")
        expect(ActiveSupport::JSON.decode(raw)['theme']).to be_eql('dark')
      end

      it 'does not share the default between records' do
        model.new.settings.theme << '!'
        expect(model.new.settings.theme).to be_eql('dark')
      end
    end

    context 'with a proc' do
      let(:default_options) { -> { { theme: 'dark', tags: [name].compact } } }

      it 'overrides the class defaults' do
        expect(model.new.settings.theme).to be_eql('dark')
      end

      it 'is evaluated on the record' do
        expect(model.new(name: 'a').settings.tags).to be_eql(%w[a])
      end
    end

    context 'with a symbol' do
      let(:default_options) { :default_settings }

      it 'calls the method on the record and overrides the class defaults' do
        expect(model.new.settings.theme).to be_eql('dark')
      end

      it 'composes the default from the record' do
        expect(model.new(name: 'a').settings.tags).to be_eql(%w[a])
      end
    end
  end

  context 'on backfill' do
    let(:model) do
      options = backfill_options
      Class.new(ActiveRecord::Base) do
        self.table_name = 'profiles'
        struct_for :settings, Profile::Settings, backfill: options
      end
    end

    subject { model.create!(name: 'a') }

    let(:document) do
      raw = connection.select_value("SELECT settings::text FROM profiles WHERE id = #{subject.id}")
      ActiveSupport::JSON.decode(raw)
    end

    before do
      connection.execute(<<~SQL)
        UPDATE profiles SET settings = '{"tags": ["a"]}' WHERE id = #{subject.id}
      SQL

      subject.reload
    end

    context 'with true' do
      let(:backfill_options) { true }

      it 'applies the class defaults to stored documents' do
        expect(subject.settings.theme).to be_eql('light')
        expect(subject.settings.notifications).to be_eql(true)
      end

      it 'marks the record as changed once the value is read' do
        expect(subject.settings.theme).to be_present
        expect(subject.changed?).to be_truthy

        subject.save!
        expect(document['theme']).to be_eql('light')
        expect(document['tags']).to be_eql(%w[a])

        expect(subject.reload.changed?).to be_falsey
      end
    end

    context 'with a list of properties' do
      let(:backfill_options) { %i[theme] }

      it 'applies only the listed defaults' do
        expect(subject.settings.theme).to be_eql('light')
        expect(subject.settings.notifications).to be_nil
      end

      it 'marks the record as changed once the value is read' do
        expect(subject.settings.theme).to be_present
        expect(subject.changed?).to be_truthy

        subject.save!
        expect(document).to be_eql('theme' => 'light', 'tags' => %w[a])
      end
    end
  end

  context 'on null semantics' do
    subject { Profile.create!(name: 'a').reload }

    let(:raw_bio) do
      connection.select_value("SELECT bio::text FROM profiles WHERE id = #{subject.id}")
    end

    it 'keeps the column null when there are no defaults' do
      expect(raw_bio).to be_nil
    end

    it 'returns an instance when the column is null' do
      expect(subject.bio).to be_a(Profile::Bio)
      expect(subject.bio.headline).to be_nil
    end

    it 'keeps the column null when the instance is never changed' do
      subject.bio.headline
      subject.update!(name: 'b')
      expect(raw_bio).to be_nil
    end

    it 'does not mark the record as dirty when reading' do
      subject.bio.headline
      expect(subject.changed?).to be_falsey
    end

    it 'stores the value once the instance is changed' do
      subject.bio.headline = 'hi'
      expect(subject.changed?).to be_truthy

      subject.save!
      expect(subject.reload.changed?).to be_falsey
      expect(subject.bio.headline).to be_eql('hi')
    end

    it 'goes back to pristine when a change is reverted' do
      subject.settings.theme = 'dark'
      expect(subject.changed?).to be_truthy

      subject.settings.theme = 'light'
      expect(subject.changed?).to be_falsey
    end

    it 'keeps the raw value byte-identical while untouched' do
      connection.execute(<<~SQL)
        UPDATE profiles SET settings = '{"zeta": 1, "theme": "dark"}' WHERE id = #{subject.id}
      SQL

      subject.reload
      query = "SELECT settings::text FROM profiles WHERE id = #{subject.id}"
      before = connection.select_value(query)

      subject.settings.theme
      subject.update!(name: 'c')
      expect(connection.select_value(query)).to be_eql(before)
    end

    it 'detects in-place mutation of nested values' do
      connection.execute(<<~SQL)
        UPDATE profiles SET settings = '{"tags": ["a"]}' WHERE id = #{subject.id}
      SQL

      subject.reload

      subject.settings.tags << 'b'
      expect(subject.changed?).to be_truthy

      subject.save!
      expect(subject.reload.settings.tags).to be_eql(%w[a b])
    end
  end

  context 'on unknown keys' do
    subject { Profile.create!(name: 'a') }

    let(:document) do
      raw = connection.select_value("SELECT settings::text FROM profiles WHERE id = #{subject.id}")
      ActiveSupport::JSON.decode(raw)
    end

    before do
      connection.execute(<<~SQL)
        UPDATE profiles SET settings = '{"theme": "dark", "legacy": 123}' WHERE id = #{subject.id}
      SQL

      subject.reload
    end

    it 'gives plain access to unknown keys' do
      expect(subject.settings[:legacy]).to be_eql(123)
    end

    it 'routes declared attributes through the accessors' do
      expect(subject.settings[:theme]).to be_eql('dark')

      subject.settings[:notifications] = 'false'
      expect(subject.settings.notifications).to be_eql(false)
    end

    it 'preserves unknown keys when the instance is stored' do
      subject.settings.theme = 'light'
      subject.save!

      expect(document['legacy']).to be_eql(123)
      expect(document['theme']).to be_eql('light')
    end

    context 'when strict' do
      it 'is the configured default' do
        expect(Torque::PostgreSQL.config.struct.default_strict).to be_truthy
        expect(settings_klass.strict?).to be_truthy
      end

      it 'raises when writing an unknown key' do
        expect do
          subject.settings[:other] = 'x'
        end.to raise_error(ActiveModel::UnknownAttributeError, /other/)
      end

      it 'raises when building an instance with an unknown key' do
        expect do
          settings_klass.new(other: 'x')
        end.to raise_error(ActiveModel::UnknownAttributeError, /other/)
      end

      it 'raises before storing a hash with an unknown key' do
        subject.settings = { other: 'x' }
        expect { subject.save! }.to raise_error(ActiveModel::UnknownAttributeError, /other/)
      end
    end

    context 'when not strict' do
      let(:struct_klass) do
        Class.new(Torque::PostgreSQL::Attributes::Struct) do
          self.strict = false

          attribute :theme, :string
        end
      end

      let(:model) do
        klass = struct_klass
        Class.new(ActiveRecord::Base) do
          self.table_name = 'profiles'
          struct_for :settings, klass
        end
      end

      subject { model.find(super().id) }

      it 'accepts the option on the struct method' do
        klass = Class.new(Torque::PostgreSQL::Attributes::Struct) { attribute :theme, :string }
        Class.new(ActiveRecord::Base) do
          self.table_name = 'profiles'
          struct_for :settings, klass, strict: false
        end

        expect(klass.strict?).to be_falsey
      end

      it 'stores unknown keys' do
        subject.settings[:legacy] = 321
        expect(subject.settings[:legacy]).to be_eql(321)
        expect(subject.settings['legacy']).to be_eql(321)

        subject.settings['legacy'] = 123
        expect(subject.settings[:legacy]).to be_eql(123)
        expect(subject.settings['legacy']).to be_eql(123)
      end

      it 'marks the instance as changed when writing unknown keys' do
        subject.settings[:other] = 'x'
        expect(subject.changed?).to be_truthy

        subject.save!
        expect(document['other']).to be_eql('x')
      end
    end
  end

  context 'on validation' do
    subject { Profile.new(name: 'a') }

    it 'skips validation while nothing is stored' do
      expect(subject.bio).to be_present
      expect(subject).to be_valid
    end

    it 'adds a plain invalid error when the instance is invalid' do
      subject.settings.theme = 'bogus'
      expect(subject).to be_invalid
      expect(subject.errors.added?(:settings, :invalid)).to be_truthy
    end

    it 'runs the validation once the value is present on the database' do
      subject.save!
      connection.execute(<<~SQL)
        UPDATE profiles SET settings = '{"theme": "bogus"}' WHERE id = #{subject.id}
      SQL

      subject.reload
      expect(subject).to be_invalid
    end

    it 'validates every entry of an array' do
      subject.previews = [{ label: 'a', url: 'http://x' }, { label: 'b' }]
      expect(subject).to be_invalid
      expect(subject.errors.added?(:previews, :invalid)).to be_truthy
    end
  end

  context 'on delegation' do
    subject { Profile.new }

    it 'delegates readers and writers to the struct' do
      subject.theme = 'dark'
      expect(subject.theme).to be_eql('dark')
      expect(subject.settings.theme).to be_eql('dark')
    end
  end

  context 'on json array columns' do
    subject { Profile.create!(name: 'a').reload }

    it 'reads null as an empty list' do
      expect(subject.previews).to be_empty
    end

    it 'keeps the column null when the list is never changed' do
      subject.previews.size
      subject.update!(name: 'b')

      raw = connection.select_value("SELECT previews::text FROM profiles WHERE id = #{subject.id}")
      expect(raw).to be_nil
    end

    it 'casts every entry to an instance' do
      subject.update!(previews: [{ label: 'a', url: 'x' }, Profile::Preview.new(label: 'b', url: 'y')])
      subject.reload

      expect(subject.previews.size).to be_eql(2)
      expect(subject.previews.map(&:class).uniq).to be_eql([Profile::Preview])
      expect(subject.previews.first.label).to be_eql('a')
    end

    it 'detects additions and mutations' do
      subject.update!(previews: [{ label: 'a', url: 'x' }])
      subject.reload

      subject.previews << Profile::Preview.new(label: 'b', url: 'y')
      expect(subject.changed?).to be_truthy

      subject.save!
      subject.reload

      subject.previews.first.label = 'c'
      expect(subject.changed?).to be_truthy

      subject.save!
      expect(subject.reload.previews.map(&:label)).to be_eql(%w[c b])
    end
  end

  context 'on native array columns' do
    subject { Profile.create!(name: 'a').reload }

    it 'reads null as an empty list' do
      expect(subject.snippets).to be_empty
    end

    it 'keeps the column null when the list is never changed' do
      subject.snippets.size
      subject.update!(name: 'b')

      raw = connection.select_value("SELECT snippets::text FROM profiles WHERE id = #{subject.id}")
      expect(raw).to be_nil
    end

    it 'casts every entry to an instance and round-trips' do
      subject.update!(snippets: [{ title: 't1', body: 'b1' }, { title: 't2', body: 'b2' }])
      subject.reload

      expect(subject.snippets.size).to be_eql(2)
      expect(subject.snippets.first).to be_a(Profile::Snippet)
      expect(subject.snippets.first.title).to be_eql('t1')
    end

    it 'detects mutations on entries' do
      subject.update!(snippets: [{ title: 't1', body: 'b1' }])
      subject.reload

      subject.snippets.first.body = 'b2'
      expect(subject.changed?).to be_truthy

      subject.save!
      expect(subject.reload.snippets.first.body).to be_eql('b2')
    end
  end

  context 'on encryption' do
    before do
      ActiveRecord::Encryption.configure(
        primary_key: 'test master key',
        deterministic_key: 'test deterministic key',
        key_derivation_salt: 'testing salt',
      )
    end

    let(:struct_klass) do
      Class.new(Torque::PostgreSQL::Attributes::Struct) do
        attribute :label, :string
        attribute :token, :string

        encrypts :token
      end
    end

    let(:model) do
      klass = struct_klass
      Class.new(ActiveRecord::Base) do
        self.table_name = 'profiles'
        struct_for :settings, klass
      end
    end

    subject { model.create!(settings: { label: 'a', token: 'secret' }) }

    it 'raises when encrypting an undeclared attribute' do
      expect do
        Class.new(Torque::PostgreSQL::Attributes::Struct) { encrypts :missing }
      end.to raise_error(ArgumentError, /declared attribute/)
    end

    it 'stores the attribute encrypted inside the document' do
      raw = connection.select_value("SELECT settings::text FROM profiles WHERE id = #{subject.id}")
      expect(raw).not_to include('secret')
      expect(ActiveSupport::JSON.decode(raw)['label']).to be_eql('a')
    end

    it 'decrypts the attribute when loading' do
      expect(subject.reload.settings.token).to be_eql('secret')
    end

    it 'does not mark unchanged records as dirty' do
      expect(subject.changed?).to be_falsey

      subject.reload
      subject.settings.label
      expect(subject.changed?).to be_falsey
    end

    it 'persists changes to the encrypted attribute' do
      subject.reload
      subject.settings.token = 'other'
      expect(subject.changed?).to be_truthy

      subject.save!
      expect(subject.reload.settings.token).to be_eql('other')
    end
  end

  context 'on instances' do
    it 'compares by class and attributes' do
      one = settings_klass.new(theme: 'dark')
      two = settings_klass.new(theme: 'dark')
      expect(one).to be_eql(two)

      two.notifications = false
      expect(one).not_to be_eql(two)
    end

    it 'only exposes the attributes that were written' do
      instance = settings_klass.new
      expect(instance.attributes).to be_eql('theme' => 'light', 'notifications' => true)

      instance.tags = %w[a]
      expect(instance.attributes).to have_key('tags')
    end

    it 'exposes the dirty methods' do
      instance = settings_klass.new
      instance.theme = 'dark'
      expect(instance.theme_changed?).to be_truthy
      expect(instance.changes).to include('theme')
    end
  end
end
