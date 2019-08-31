require 'spec_helper'

RSpec.describe 'Enum' do
  let(:connection) { ActiveRecord::Base.connection }
  let(:attribute_klass) { Torque::PostgreSQL::Attributes::EnumSet }

  def decorate(model, field, options = {})
    attribute_klass.include_on(model, :enum_set)
    model.enum_set(field, **options)
  end

  before :each do
    Torque::PostgreSQL.config.enum.set_method = :pg_set_enum
    Torque::PostgreSQL::Attributes::EnumSet.include_on(ActiveRecord::Base)

    # Define a method to find yet to define constants
    Torque::PostgreSQL.config.enum.namespace.define_singleton_method(:const_missing) do |name|
      Torque::PostgreSQL::Attributes::EnumSet.lookup(name)
    end

    # Define a helper method to get a sample value
    Torque::PostgreSQL.config.enum.namespace.define_singleton_method(:sample) do |name|
      Torque::PostgreSQL::Attributes::EnumSet.lookup(name).sample
    end
  end

  context 'on table definition' do
    subject { ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.new('articles') }

    it 'can be defined as an array' do
      subject.enum(:content_status, array: true)
      expect(subject['content_status'].name).to be_eql('content_status')
      expect(subject['content_status'].type).to be_eql(:content_status)

      array = subject['content_status'].respond_to?(:options) \
        ? subject['content_status'].options[:array] \
        : subject['content_status'].array

      expect(array).to be_eql(true)
    end
  end

  context 'on schema' do
    it 'can be used on tables' do
      dump_io = StringIO.new
      checker = /t\.enum +"conflicts", +array: true, +subtype: :conflicts/
      ActiveRecord::SchemaDumper.dump(connection, dump_io)
      expect(dump_io.string).to match checker
    end

    it 'can have a default value as an array of symbols' do
      dump_io = StringIO.new
      checker = /t\.enum +"types", +default: \[:A, :B\], +array: true, +subtype: :types/
      ActiveRecord::SchemaDumper.dump(connection, dump_io)
      expect(dump_io.string).to match checker
    end
  end

  context 'on value' do
    subject { Enum::TypesSet }
    let(:values) { %w(A B C D) }
    let(:error) { Torque::PostgreSQL::Attributes::EnumSet::EnumSetError }
    let(:mock_enum) do
      enum_klass = Class.new(subject::EnumSource.superclass)
      enum_klass.instance_variable_set(:@values, values << '15')

      klass = Class.new(subject.superclass)
      klass.const_set('EnumSource', enum_klass)
      klass
    end

    it 'class exists' do
      namespace = Torque::PostgreSQL.config.enum.namespace
      expect(namespace.const_defined?('TypesSet')).to be_truthy
      expect(subject.const_defined?('EnumSource')).to be_truthy
      expect(subject < Torque::PostgreSQL::Attributes::EnumSet).to be_truthy
    end

    it 'returns the db type name' do
      expect(subject.type_name).to be_eql('types[]')
    end

    it 'values match database values' do
      expect(subject.values).to be_eql(values)
    end

    it 'values can be reach using fetch, as in hash enums' do
      expect(subject).to respond_to(:fetch)

      value = subject.fetch('A', 'A')
      expect(value).to be_a(subject)
      expect(value).to be_eql(subject.A)

      value = subject.fetch('other', 'other')
      expect(value).to be_nil
    end

    it 'values can be reach using [], as in hash enums' do
      expect(subject).to respond_to(:[])

      value = subject['A']
      expect(value).to be_a(subject)
      expect(value).to be_eql(subject.A)

      value = subject['other']
      expect(value).to be_nil
    end

    it 'accepts respond_to against value' do
      expect(subject).to respond_to(:A)
    end

    it 'allows fast creation of values' do
      value = subject.A
      expect(value).to be_a(subject)
    end

    it 'keeps blank values as Lazy' do
      expect(subject.new(nil)).to be_nil
      expect(subject.new([])).to be_blank
    end

    it 'can start from nil value using lazy' do
      lazy  = Torque::PostgreSQL::Attributes::Lazy
      value = subject.new(nil)

      expect(value.__class__).to be_eql(lazy)
      expect(value.to_s).to be_eql('')
      expect(value.to_i).to be_nil

      expect(value.A?).to be_falsey
    end

    it 'accepts values to come from numeric as power' do
      expect(subject.new(0)).to be_blank
      expect(subject.new(1)).to be_eql(subject.A)
      expect(subject.new(3)).to be_eql(subject.A | subject.B)
      expect { subject.new(16) }.to raise_error(error, /out of bounds/)
    end

    it 'accepts values to come from numeric list' do
      expect(subject.new([0])).to be_eql(subject.A)
      expect(subject.new([0, 1])).to be_eql(subject.A | subject.B)
      expect { subject.new([4]) }.to raise_error(error.superclass, /out of bounds/)
    end

    it 'accepts string initialization' do
      expect(subject.new('A')).to be_eql(subject.A)
      expect { subject.new('E') }.to raise_error(error.superclass, /not valid for/)
    end

    it 'allows values bitwise operations' do
      expect((subject.A | subject.B).to_i).to be_eql(3)
      expect((subject.A & subject.B).to_i).to be_nil
      expect(((subject.A | subject.B) & subject.B).to_i).to be_eql(2)
    end

    it 'allows values comparison' do
      value = subject.B | subject.C
      expect(value).to be > subject.A
      expect(value).to be < subject.D
      expect(value).to be_eql(6)
      expect(value).to_not be_eql(1)
      expect(subject.A == mock_enum.A).to be_falsey
    end

    it 'accepts value checking' do
      value = subject.B | subject.C
      expect(value).to respond_to(:B?)
      expect(value.B?).to be_truthy
      expect(value.C?).to be_truthy
      expect(value.A?).to be_falsey
      expect(value.D?).to be_falsey
    end

    it 'accepts replace and bang value' do
      value = subject.B | subject.C
      expect(value).to respond_to(:B!)
      expect(value.A!).to be_eql(7)
      expect(value.replace(:D)).to be_eql(subject.D)
    end

    it 'accepts values turn into integer by its power' do
      expect(subject.B.to_i).to be_eql(2)
      expect(subject.C.to_i).to be_eql(4)
    end

    it 'accepts values turn into an array of integer by index' do
      expect((subject.B | subject.C).map(&:to_i)).to be_eql([1, 2])
    end

    it 'can return a sample for resting purposes' do
      expect(subject).to receive(:new).with(Numeric)
      subject.sample
    end
  end

  context 'on OID' do
    let(:enum) { Enum::TypesSet }
    let(:enum_source) { enum::EnumSource }
    subject { Torque::PostgreSQL::Adapter::OID::EnumSet.new('types', enum_source) }

    context 'on deserialize' do
      it 'returns nil' do
        expect(subject.deserialize(nil)).to be_nil
      end

      it 'returns enum' do
        value = subject.deserialize('{B,C}')
        expect(value).to be_a(enum)
        expect(value).to be_eql(enum.B | enum.C)
      end
    end

    context 'on serialize' do
      it 'returns nil' do
        expect(subject.serialize(nil)).to be_nil
        expect(subject.serialize(0)).to be_nil
      end

      it 'returns as string' do
        expect(subject.serialize(enum.B | enum.C)).to be_eql('{B,C}')
        expect(subject.serialize(3)).to be_eql('{A,B}')
      end
    end

    context 'on cast' do
      it 'accepts nil' do
        expect(subject.cast(nil)).to be_nil
      end

      it 'accepts invalid values as nil' do
        expect(subject.cast([])).to be_nil
      end

      it 'accepts array of strings' do
        value = subject.cast(['A'])
        expect(value).to be_a(enum)
        expect(value).to be_eql(enum.A)
      end

      it 'accepts array of numbers' do
        value = subject.cast([1])
        expect(value).to be_a(enum)
        expect(value).to be_eql(enum.B)
      end
    end
  end

  context 'on I18n' do
    subject { Enum::TypesSet }

    it 'has the text method' do
      expect(subject.new(0)).to respond_to(:text)
    end

    it 'brings the correct values' do
      expect(subject.new(0).text).to be_eql('')
      expect(subject.new(1).text).to be_eql('A')
      expect(subject.new(2).text).to be_eql('B')
      expect(subject.new(3).text).to be_eql('A and B')
      expect(subject.new(7).text).to be_eql('A, B, and C')
    end
  end

  context 'on model' do
    before(:each) { decorate(Course, :types) }

    subject { Course }
    let(:instance) { Course.new }

    it 'has all enum set methods' do
      expect(subject).to  respond_to(:types)
      expect(subject).to  respond_to(:types_texts)
      expect(subject).to  respond_to(:types_options)
      expect(instance).to respond_to(:types_text)

      subject.types.each do |value|
        expect(subject).to  respond_to(value)
        expect(instance).to respond_to(value + '?')
        expect(instance).to respond_to(value + '!')
      end
    end
  end
end
