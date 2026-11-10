require 'spec_helper'

RSpec.describe 'Composite' do
  let(:connection) { ActiveRecord::Base.connection }
  let(:source) { ActiveRecord::Base.connection_pool }

  context 'on migration' do
    it 'creates a composite type' do
      connection.create_composite_type(:sample_type) do |t|
        t.string  'label'
        t.integer 'amount'
      end

      expect(connection.type_exists?(:sample_type)).to be_truthy

      columns = connection.composite_column_types('sample_type')
      expect(columns.keys).to be_eql(%w[label amount])
      expect(columns['amount'].type).to be_eql(:integer)
    ensure
      connection.drop_type(:sample_type)
    end

    it 'accepts size-related and type-related options' do
      connection.create_composite_type(:sample_type) do |t|
        t.string    'label', limit: 10
        t.enum      'category', enum_type: :types
        t.composite 'place', composite_type: :address
        t.string    'tags', array: true
      end

      columns = connection.composite_column_types('sample_type')
      expect(columns['category']).to be_a(Torque::PostgreSQL::Adapter::OID::Enum)
      expect(columns['place']).to be_a(Torque::PostgreSQL::Adapter::OID::Composite)
    ensure
      connection.drop_type(:sample_type)
    end

    it 'raises on unsupported column options' do
      expect do
        connection.create_composite_type(:sample_type) do |t|
          t.string 'label', null: false
        end
      end.to raise_error(ArgumentError, /unsupported options/)

      expect do
        connection.create_composite_type(:sample_type) do |t|
          t.string 'label', default: 'x'
        end
      end.to raise_error(ArgumentError, /unsupported options/)
    end

    it 'raises on indexes' do
      expect do
        connection.create_composite_type(:sample_type) do |t|
          t.string 'label', index: true
        end
      end.to raise_error(ArgumentError)
    end

    it 'raises when composite columns do not provide the type' do
      expect { connection.type_to_sql(:composite) }
        .to raise_error(ArgumentError, /composite_type is required/)
    end

    it 'raises when the type already exists' do
      expect do
        connection.create_composite_type(:address) { |t| t.string 'other' }
      end.to raise_error(ActiveRecord::StatementInvalid, /already exists/)
    end

    it 'changes the columns of a composite type' do
      connection.create_composite_type(:sample_type) do |t|
        t.string  'label'
        t.integer 'amount'
        t.string  'gone'
      end

      connection.change_composite_type(:sample_type) do |t|
        t.date   'issued_at'
        t.change 'amount', :bigint
        t.remove 'gone'
        t.rename 'label', 'title'
      end

      columns = connection.composite_column_types('sample_type')
      expect(columns.keys).to be_eql(%w[title amount issued_at])
      expect(columns['amount'].type).to be_eql(:integer)
      expect(columns['amount'].limit).to be_eql(8)
      expect(columns['issued_at'].type).to be_eql(:date)
    ensure
      connection.drop_type(:sample_type, check: true)
    end

    it 'keeps the schema out of the columns while changing a type' do
      connection.create_composite_type(:sample_type, schema: 'internal') { |t| t.string 'label' }
      connection.add_composite_column(:sample_type, 'amount', :integer, schema: 'internal')

      columns = connection.composite_column_types('internal.sample_type')
      expect(columns.keys).to be_eql(%w[label amount])
    ensure
      connection.drop_type(:sample_type, schema: 'internal', check: true)
    end

    it 'raises on unsupported options when changing a composite type' do
      expect do
        connection.change_composite_type(:sample_type) { |t| t.string 'label', null: false }
      end.to raise_error(ArgumentError, /unsupported options/)
    end

    it 'changes a composite type one column at a time' do
      connection.create_composite_type(:sample_type) { |t| t.string 'label' }

      connection.add_composite_column(:sample_type, 'amount', :integer)
      connection.change_composite_column(:sample_type, 'amount', :bigint)
      connection.rename_composite_column(:sample_type, 'label', 'title')
      connection.add_composite_column(:sample_type, 'gone', :string)
      connection.remove_composite_column(:sample_type, 'gone')

      columns = connection.composite_column_types('sample_type')
      expect(columns.keys).to be_eql(%w[title amount])
      expect(columns['amount'].limit).to be_eql(8)
    ensure
      connection.drop_type(:sample_type, check: true)
    end

    it 'recreates the type with force' do
      connection.create_composite_type(:sample_type) { |t| t.string 'a' }
      connection.create_composite_type(:sample_type, force: :cascade) { |t| t.string 'b' }

      expect(connection.composite_column_types('sample_type').keys).to be_eql(%w[b])
    ensure
      connection.drop_type(:sample_type)
    end

    context 'reverting' do
      let(:migration) { ActiveRecord::Migration::Current.new('Testing') }

      before do
        allow_any_instance_of(ActiveRecord::Migration).to receive(:puts)
        connection.create_composite_type(:sample_type) { |t| t.string 'label' }
      end

      it 'reverts the creation of a composite type' do
        expect(connection.type_exists?(:sample_type)).to be_truthy

        migration.revert do
          migration.connection.create_composite_type(:sample_type) { |t| t.string 'label' }
        end

        expect(connection.type_exists?(:sample_type)).to be_falsey
      end

      it 'reverts a column being added to a composite type' do
        migration.connection.add_composite_column(:sample_type, 'amount', :integer)
        expect(connection.composite_column_types('sample_type').keys).to include('amount')

        migration.revert do
          migration.connection.add_composite_column(:sample_type, 'amount', :integer)
        end

        expect(connection.composite_column_types('sample_type').keys).not_to include('amount')
      ensure
        connection.drop_type(:sample_type, check: true)
      end

      it 'reverts a column being renamed' do
        migration.revert do
          migration.connection.rename_composite_column(:sample_type, 'title', 'label')
        end

        expect(connection.composite_column_types('sample_type').keys).to be_eql(%w[title])
      ensure
        connection.drop_type(:sample_type, check: true)
      end

      it 'does not revert a composite type being changed' do
        expect do
          migration.revert do
            migration.connection.change_composite_type(:sample_type) { |t| t.string 'other' }
          end
        end.to raise_error(ActiveRecord::IrreversibleMigration)
      ensure
        connection.drop_type(:sample_type, check: true)
      end

      it 'does not revert a column being removed without a type' do
        expect do
          migration.revert do
            migration.connection.remove_composite_column(:sample_type, 'gone')
          end
        end.to raise_error(ActiveRecord::IrreversibleMigration)
      ensure
        connection.drop_type(:sample_type, check: true)
      end

      it 'reverts a column being removed when given a type' do
        migration.revert do
          migration.connection.remove_composite_column(:sample_type, 'gone', :string)
        end

        expect(connection.composite_column_types('sample_type').keys).to include('gone')
      ensure
        connection.drop_type(:sample_type, check: true)
      end
    end

    context 'with tables' do
      before(:context) { ActiveRecord::Base.connection.max_identifier_length }

      mock_create_table

      it 'adds composite columns through the helper' do
        sql = connection.create_table(:sample, id: false) do |t|
          t.composite 'home', composite_type: :address
        end

        expect(sql).to include('"home" address')
      end

      it 'supports arrays of composite columns' do
        sql = connection.create_table(:sample, id: false) do |t|
          t.composite 'homes', composite_type: :address, array: true
        end

        expect(sql).to include('"homes" address[]')
      end

      it 'supports the type name as the column type' do
        sql = connection.create_table(:sample, id: false) do |t|
          t.column 'home', :address
        end

        expect(sql).to include('"home" address')
      end
    end
  end

  context 'on discovery' do
    it 'lists user defined composite types' do
      expect(connection.composite_types).to include('address', 'full_address')
    end

    it 'sorts the list by dependencies' do
      list = connection.composite_types
      expect(list.index('address')).to be < list.index('full_address')
    end

    it 'does not include table row types' do
      expect(connection.composite_types & connection.tables).to be_empty
    end

    it 'identifies composite columns' do
      column = Place.columns_hash['home']
      expect(column.type).to be_eql(:composite)
      expect(column.sql_type).to be_eql('address')

      column = Place.columns_hash['offices']
      expect(column.type).to be_eql(:composite)
      expect(column.array?).to be_truthy
    end
  end

  context 'on classes' do
    it 'spins up classes on demand' do
      klass = Composite::Address
      expect(klass.superclass).to be_eql(Torque::PostgreSQL::Attributes::Composite)
      expect(klass.type_name).to be_eql('address')
    end

    it 'defines the attributes from the type columns' do
      instance = Composite::Address.new(street: 'Main', number: '42')
      expect(instance.street).to be_eql('Main')
      expect(instance.number).to be_eql(42)
      expect(Composite::Address.attribute_names).to include('street', 'city', 'number', 'category')
    end

    it 'compares instances by class and attributes' do
      one = Composite::Address.new(street: 'X', number: 1)
      two = Composite::Address.new(street: 'X', number: 1)

      expect(one).to be_eql(two)

      two.number = 2
      expect(one).not_to be_eql(two)
    end

    it 'exposes the attributes as a hash' do
      instance = Composite::Address.new(street: 'X')
      expect(instance.to_h).to include(street: 'X', number: nil)
    end

    it 'keeps the attributes that the class declares on its own' do
      klass = Class.new(Torque::PostgreSQL::Attributes::Composite)
      klass.type_name = 'address'
      klass.attribute(:number, :string)

      expect(klass.attribute_types['number']).to be_a(ActiveModel::Type::String)
      expect(klass.new(number: 42).number).to be_eql('42')
      expect(klass.columns['number'].type).to be_eql(:integer)
    end

    it 'supports irregular types mapping' do
      stub_klass = Class.new(Torque::PostgreSQL::Attributes::Composite)
      Object.const_set('SpecialAddress', stub_klass)
      Torque::PostgreSQL.config.composite.irregular_types = { address: 'SpecialAddress' }

      expect(Torque::PostgreSQL::Attributes::Composite.lookup('address')).to be_eql(stub_klass)
    ensure
      Torque::PostgreSQL.config.composite.irregular_types = {}
      Object.send(:remove_const, 'SpecialAddress')
    end
  end

  context 'on OID' do
    subject { Torque::PostgreSQL::Adapter::OID::Composite.new('address') }

    it 'deserializes literals with quoting edge cases' do
      instance = subject.deserialize(%q{("say ""hi"", ok",,"1",A)})
      expect(instance.street).to be_eql('say "hi", ok')
      expect(instance.city).to be_nil
      expect(instance.number).to be_eql(1)
      expect(instance.category).to be_eql('A')
    end

    it 'differentiates nil and empty string columns' do
      instance = subject.deserialize(%q{("",,,)})
      expect(instance.street).to be_eql('')
      expect(instance.city).to be_nil
    end

    it 'casts hashes, arrays, instances, and nil' do
      expect(subject.cast(nil)).to be_nil
      expect(subject.cast(street: 'X').street).to be_eql('X')
      expect(subject.cast(['X', 'Y', 2, nil]).city).to be_eql('Y')

      instance = Composite::Address.new(street: 'X')
      expect(subject.cast(instance)).to be_eql(instance)
    end

    it 'serializes into an encoder and its values' do
      data = subject.serialize(Composite::Address.new(street: 'X', number: 1))
      expect(data).to be_a(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array::Data)
      expect(data.encoder).to be_a(PG::TextEncoder::Record)
      expect(data.values).to be_eql(['X', nil, 1, nil])
      expect(subject.serialize(nil)).to be_nil
    end

    it 'deserializes back from what it serialized' do
      instance = Composite::Address.new(street: 'X', number: 1)
      expect(subject.deserialize(subject.serialize(instance))).to be_eql(instance)
    end

    it 'detects in-place changes' do
      raw = %q{(Main,,1,)}
      expect(subject.changed_in_place?(raw, subject.deserialize(raw))).to be_falsey
      expect(subject.changed_in_place?(raw, Composite::Address.new(street: 'Other'))).to be_truthy
    end
  end

  context 'on records' do
    it 'round-trips composite values' do
      place = Place.create!(name: 'HQ', home: { street: 'Main, St', number: 1, category: 'A' })
      place.reload

      expect(place.home).to be_a(Composite::Address)
      expect(place.home.street).to be_eql('Main, St')
      expect(place.home.number).to be_eql(1)
      expect(place.home.category).to be_eql('A')
    end

    it 'round-trips tricky quoting values' do
      tricky = { street: %q{say "hi", ok\maybe}, city: '', number: nil }
      place = Place.create!(name: 'Edge', home: tricky)
      place.reload

      expect(place.home.street).to be_eql(%q{say "hi", ok\maybe})
      expect(place.home.city).to be_eql('')
      expect(place.home.number).to be_nil
    end

    it 'round-trips arrays of composite values' do
      offices = [{ street: 'A' }, Composite::Address.new(street: 'B, "C"')]
      place = Place.create!(name: 'Multi', offices: offices)
      place.reload

      expect(place.offices.size).to be_eql(2)
      expect(place.offices.map(&:class).uniq).to be_eql([Composite::Address])
      expect(place.offices.last.street).to be_eql('B, "C"')
    end

    it 'round-trips nested composite values' do
      location = { base: { street: 'Deep', number: 7 }, country: 'BR' }
      place = Place.create!(name: 'Nested', location: location)
      place.reload

      expect(place.location).to be_a(Composite::FullAddress)
      expect(place.location.country).to be_eql('BR')
      expect(place.location.base).to be_a(Composite::Address)
      expect(place.location.base.number).to be_eql(7)
    end

    it 'round-trips columns that are not plain strings' do
      location = { country: 'BR', since: Date.new(2020, 3, 1), rate: BigDecimal('12.34') }
      place = Place.create!(name: 'Typed', location: location)
      place.reload

      expect(place.location.since).to be_eql(Date.new(2020, 3, 1))
      expect(place.location.rate).to be_eql(BigDecimal('12.34'))
    end

    it 'does not mark untouched records as dirty' do
      place = Place.create!(name: 'Clean', home: { street: 'S' })
      place.reload

      place.home.street
      expect(place.changed?).to be_falsey
    end

    it 'marks assignment changes as dirty' do
      place = Place.create!(name: 'Dirty', home: { street: 'S' })
      place.reload

      place.home = { street: 'Other' }
      expect(place.changed?).to be_truthy

      place.save!
      expect(place.reload.home.street).to be_eql('Other')
    end

    it 'supports composite values on where clauses' do
      place = Place.create!(name: 'Find', home: { street: 'Unique St', number: 9 })

      found = Place.where(home: place.reload.home).first
      expect(found).to be_eql(place)
    end
  end

  context 'on null semantics' do
    subject { Place.create!(name: 'Null').reload }

    let(:raw_home) do
      connection.select_value("SELECT home::text FROM places WHERE id = #{subject.id}")
    end

    it 'reads a null column as nil, which is blank' do
      expect(subject.home).to be_nil
      expect(subject.home).to be_blank
      expect(subject.offices).to be_nil
      expect(subject.offices).to be_blank
    end

    it 'keeps the column null when the record is saved again' do
      subject.update!(name: 'Still null')
      expect(raw_home).to be_nil
    end

    it 'does not validate a null value' do
      expect(Place.new(name: 'Null')).to be_valid
    end

    # A composite always carries every one of its columns, so a row of nulls is
    # a value on its own, which PostgreSQL keeps apart from a null column
    it 'is never blank once there is a value' do
      expect(Composite::Address.new).not_to be_empty
      expect(Composite::Address.new).to be_present
    end

    it 'stores a value with no columns set as a row of nulls' do
      subject.update!(home: {})

      expect(raw_home).to be_eql('(,,,)')
      expect(subject.reload.home).to be_a(Composite::Address)
      expect(subject.home).to be_present
    end
  end

  context 'on enum' do
    let(:enum_klass) do
      klass = Class.new(Torque::PostgreSQL::Attributes::Composite)
      klass.type_name = 'address'
      klass.enum(:category, { alpha: 'A', beta: 'B' })
      klass
    end

    it 'declares over the type loaded from the database' do
      expect(enum_klass.attribute_types['category']).to be_a(ActiveRecord::Enum::EnumType)
      expect(enum_klass.attribute_types['number'].type).to be_eql(:integer)
    end

    it 'casts the value both ways' do
      instance = enum_klass.new(category: 'alpha')

      expect(instance.category).to be_eql('alpha')
      expect(instance.alpha?).to be_truthy
      expect(instance.beta?).to be_falsey
    end

    it 'serializes through the composite type' do
      type = Torque::PostgreSQL::Adapter::OID::Composite.new('address')
      allow(type).to receive(:klass).and_return(enum_klass)

      data = type.serialize(enum_klass.new(street: 'M', category: 'alpha'))
      expect(data.values).to be_eql(['M', nil, nil, 'A'])
    end

    it 'does not define anything that needs a relation' do
      expect(enum_klass.new).not_to respond_to(:alpha!)
      expect(enum_klass).not_to respond_to(:alpha)
    end
  end

  context 'on normalization' do
    let(:extended_klass) do
      klass = Class.new(Torque::PostgreSQL::Attributes::Composite)
      klass.type_name = 'address'
      klass.normalizes(:street, with: ->(value) { value.strip.upcase })
      klass
    end

    it 'normalizes a column on assignment' do
      expect(extended_klass.new(street: '  main ').street).to be_eql('MAIN')
    end
  end

  context 'on store accessor' do
    let(:extended_klass) do
      klass = Class.new(Torque::PostgreSQL::Attributes::Composite)
      klass.type_name = 'address'
      klass.attribute(:extras, ActiveRecord::Type::Json.new)
      klass.store_accessor(:extras, :locale)
      klass
    end

    it 'expands the keys of a json attribute' do
      instance = extended_klass.new
      instance.locale = 'pt-BR'

      expect(instance.locale).to be_eql('pt-BR')
      expect(instance.extras).to be_eql('locale' => 'pt-BR')
      expect(instance.locale_changed?).to be_truthy
    end
  end

  context 'on json serialization' do
    it 'serializes the columns, and not the internals' do
      instance = Composite::Address.new(street: 'Main', number: 1)

      expect(instance.as_json).to be_eql(
        'street' => 'Main',
        'city' => nil,
        'number' => 1,
        'category' => nil,
      )
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

    let(:composite_klass) do
      klass = Class.new(Torque::PostgreSQL::Attributes::Composite)
      klass.type_name = 'address'
      klass.encrypts :street
      klass
    end

    let(:type) do
      oid = Torque::PostgreSQL::Adapter::OID::Composite.new('address')
      allow(oid).to receive(:klass).and_return(composite_klass)
      oid
    end

    it 'raises when encrypting an undeclared attribute' do
      klass = Class.new(Torque::PostgreSQL::Attributes::Composite)
      klass.type_name = 'address'

      expect { klass.encrypts :missing }.to raise_error(ArgumentError, /declared attribute/)
    end

    it 'stores the column encrypted inside the record' do
      data = type.serialize(composite_klass.new(street: 'secret', number: 1))

      expect(data.values.first).not_to include('secret')
      expect(data.values.first).to include('"p"')
      expect(data.values.third).to be_eql(1)
    end

    it 'reads the column back decrypted' do
      data = type.serialize(composite_klass.new(street: 'secret', number: 1))

      expect(type.deserialize(data).street).to be_eql('secret')
      expect(type.deserialize(data).number).to be_eql(1)
    end

    it 'round-trips through the record literal' do
      data = type.serialize(composite_klass.new(street: 'secret'))
      literal = connection.quote(data)[1..-2].gsub("''", "'")

      expect(type.deserialize(literal).street).to be_eql('secret')
    end

    it 'registers the encrypted columns' do
      expect(composite_klass.encrypted_attributes).to include(:street)
      expect(composite_klass.new(street: 'secret').encrypted_attribute?(:street)).to be_falsey
    end

    it 'exposes the ciphertext of a column read from the database' do
      data = type.serialize(composite_klass.new(street: 'secret'))
      instance = type.deserialize(data)

      expect(instance.ciphertext_for(:street)).to include('"p"')
      expect(instance.encrypted_attribute?(:street)).to be_truthy
    end

    it 'supports deterministic encryption' do
      klass = Class.new(Torque::PostgreSQL::Attributes::Composite)
      klass.type_name = 'address'
      klass.encrypts :street, deterministic: true

      other = Torque::PostgreSQL::Adapter::OID::Composite.new('address')
      allow(other).to receive(:klass).and_return(klass)

      one = other.serialize(klass.new(street: 'same')).values.first
      two = other.serialize(klass.new(street: 'same')).values.first
      expect(one).to be_eql(two)
    end
  end

  context 'on where clauses' do
    let(:address) { Composite::Address.new(street: 'Main', number: 9) }
    let!(:place) { Place.create!(name: 'Find', home: { street: 'Main', number: 9 }) }
    let!(:many) { Place.create!(name: 'Many', offices: [{ street: 'A' }, { street: 'B' }]) }

    it 'casts whole values to the type they belong to' do
      expect(Place.where(home: address).to_sql)
        .to include(%{"places"."home" = '("Main",,"9",)'::address})

      expect(Place.where(home: place.reload.home).first).to be_eql(place)
    end

    it 'breaks a hash into conditions over each column' do
      expect(Place.where(home: { street: 'Main' }).to_sql)
        .to include(%{(("places"."home")."street" = 'Main')})

      expect(Place.where(home: { street: 'Main', number: 9 }).first).to be_eql(place)
      expect(Place.where(home: { street: 'Other' }).first).to be_nil
    end

    it 'hands each column back to the predicate builder' do
      expect(Place.where(home: { number: 1..15 }).to_sql)
        .to include(%{(("places"."home")."number" BETWEEN 1 AND 15)})

      expect(Place.where(home: { street: %w[Main Other] }).to_sql)
        .to include(%{(("places"."home")."street" IN ('Main', 'Other'))})

      expect(Place.where(home: { number: 1..15 }).first).to be_eql(place)
      expect(Place.where(home: { street: %w[Main Other] }).first).to be_eql(place)
    end

    it 'reaches columns of nested composite types' do
      expect(Place.where(location: { base: { street: 'X' } }).to_sql)
        .to include(%{((("places"."location")."base")."street" = 'X')})

      nested = Place.create!(name: 'Nested', location: { base: { street: 'X' } })
      expect(Place.where(location: { base: { street: 'X' } }).first).to be_eql(nested)
    end

    it 'checks if any entry of an array matches a hash' do
      expect(Place.where(offices: { street: 'B' }).to_sql).to include(<<~SQL.squish)
        EXISTS (SELECT 1 FROM UNNEST("places"."offices") "address"
        WHERE (("address")."street" = 'B'))
      SQL

      expect(Place.where(offices: { street: 'B' }).first).to be_eql(many)
      expect(Place.where(offices: { street: 'C' }).first).to be_nil
    end

    it 'compares whole values against the entries of an array' do
      expect(Place.where(offices: address).to_sql)
        .to include(%{'("Main",,"9",)'::address = ANY("places"."offices")})

      expect(Place.where(offices: [address]).to_sql)
        .to include(%{"places"."offices" && '{"(\\"Main\\",,\\"9\\",)"}'::address[]})

      expect(Place.where(offices: many.reload.offices.first).first).to be_eql(many)
      expect(Place.where(offices: many.offices).first).to be_eql(many)
    end

    it 'lists whole values on a plain column' do
      other = Composite::Address.new(street: 'Side', number: 1)

      expect(Place.where(home: [address, other]).to_sql)
        .to include(%{"places"."home" IN ('("Main",,"9",)'::address, '("Side",,"1",)'::address)})
      expect(Place.where(home: [address, other]).first).to be_eql(place)
      expect(Place.where(home: [other]).first).to be_nil
    end

    it 'loads the columns without a permanent connection' do
      expect(ActiveRecord::Base).not_to receive(:connection)

      Composite::Address.reset_columns!
      expect(Composite::Address.new(street: 'Main').street).to be_eql('Main')
    end

    it 'checks each entry of a list of hashes' do
      expect(Place.where(offices: [{ street: 'A' }, { street: 'B' }]).to_sql)
        .to include('EXISTS', 'OR')

      expect(Place.where(offices: [{ street: 'B' }]).first).to be_eql(many)
      expect(Place.where(offices: [{ street: 'C' }]).first).to be_nil
    end

    it 'raises when a key is not a column of the composite type' do
      expect { Place.where(home: { nope: 1 }).to_sql }
        .to raise_error(ArgumentError, /not a column of the "address"/)

      expect { Place.where(home: { nope: { deep: 1 } }).to_sql }
        .to raise_error(ArgumentError, /not a column of the "address"/)
    end
  end

  context 'on ordering and grouping' do
    let!(:first) { Place.create!(name: 'a', home: { street: 'Main', number: 9 }) }
    let!(:second) { Place.create!(name: 'b', home: { street: 'Side', number: 1 }) }

    it 'orders by a column' do
      expect(Place.order(home: { street: :desc }).to_sql)
        .to include(%{ORDER BY ("places"."home")."street" DESC})

      expect(Place.order(home: { street: :desc }).pluck(:name)).to be_eql(%w[b a])
      expect(Place.order(home: { number: :asc }).pluck(:name)).to be_eql(%w[b a])
    end

    it 'orders by the whole value' do
      expect(Place.order(:home).to_sql).to include(%{ORDER BY "places"."home" ASC})
      expect(Place.order(:home).pluck(:name)).to be_eql(%w[a b])
    end

    it 'groups by a column' do
      expect(Place.group(home: :street).to_sql).to include(%{GROUP BY ("places"."home")."street"})
      expect(Place.group(home: :street).count).to be_eql('Main' => 1, 'Side' => 1)
    end

    it 'filters groups with having' do
      expect(Place.group(:home).having(home: { street: 'Main' }).to_sql)
        .to include(%{HAVING (("places"."home")."street" = 'Main')})

      expect(Place.group(home: :street).having(home: { street: 'Main' }).count)
        .to be_eql('Main' => 1)
    end

    it 'plucks a column' do
      expect(Place.order(:name).pluck(home: :number)).to be_eql([9, 1])
    end

    it 'raises when a key is not a column of the composite type' do
      expect { Place.order(home: { nope: :asc }).to_sql }
        .to raise_error(ArgumentError, /not a column of the "address"/)
    end
  end

  context 'on validation' do
    let(:validator) { Torque::PostgreSQL::Validations::NestedValidator }

    let(:invalid_address) do
      Composite::Address.new(street: 'Main').tap do |address|
        allow(address).to receive(:invalid?).and_return(true)
      end
    end

    it 'invalidates the record that holds an invalid composite value' do
      place = Place.new(name: 'Broken', home: invalid_address)

      expect(place).to be_invalid
      expect(place.errors[:home]).to be_present
    end

    it 'invalidates the record when an entry of an array is invalid' do
      place = Place.new(name: 'Broken', offices: [invalid_address])

      expect(place).to be_invalid
      expect(place.errors[:offices]).to be_present
    end

    it 'keeps records with valid composite values valid' do
      expect(Place.new(name: 'Fine', home: { street: 'Main' })).to be_valid
    end

    it 'validates the attributes that are also normalized' do
      klass = Class.new(Place) do
        normalizes :home, with: ->(value) { value }
      end

      place = klass.new(name: 'Broken', home: invalid_address)

      expect(place).to be_invalid
      expect(place.errors.attribute_names).to include(:home)
    end

    it 'only validates the attributes backed by a composite type' do
      Place.new

      attributes = Place.validators.grep(validator).flat_map(&:attributes)
      expect(attributes).to be_eql(%w[home offices location])
    end

    it 'leaves models without composite columns alone' do
      Author.new
      Comment.new

      expect(Author.validators).to be_none(validator)
      expect(Comment.validators).to be_none(validator)
    end

    it 'does not add the validation again when the schema is reloaded' do
      Place.reset_column_information
      Place.new

      attributes = Place.validators.grep(validator).flat_map(&:attributes)
      expect(attributes).to be_eql(%w[home offices location])
    end
  end

  context 'on schema' do
    let(:dump_result) do
      ActiveRecord::SchemaDumper.dump(source, (dump_result = StringIO.new))
      dump_result.string
    end

    it 'dumps composite types after enums' do
      enum_pos = dump_result.index('create_enum "types"')
      type_pos = dump_result.index('create_composite_type "address", force: :cascade do |t|')
      table_pos = dump_result.index('create_table')

      expect(enum_pos).to be < type_pos
      expect(type_pos).to be < table_pos
    end

    it 'dumps composite types sorted by dependencies' do
      address_pos = dump_result.index('create_composite_type "address", force: :cascade do |t|')
      full_pos = dump_result.index('create_composite_type "full_address", force: :cascade do |t|')

      expect(address_pos).to be < full_pos
    end

    it 'dumps the columns of composite types' do
      expect(dump_result).to include('t.enum "category", enum_type: "types"')
      expect(dump_result).to include('t.composite "base", composite_type: "address"')
    end

    it 'does not dump table row types' do
      expect(dump_result).not_to match(/create_composite_type "(places|users|authors)"/)
    end

    it 'dumps composite columns on tables' do
      expect(dump_result).to include('t.composite "home", composite_type: "address"')
      expect(dump_result).to match(/t\.composite "offices", (?:composite_type: "address", array: true|array: true, composite_type: "address")/)
      expect(dump_result).to include('t.composite "location", composite_type: "full_address"')
    end
  end
end
