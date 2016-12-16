require 'spec_helper'

RSpec.describe 'Enum' do
  before(:each) { ActiveRecord::Base.connection.drop_type(:status) }
  after(:all) { ActiveRecord::Base.connection.drop_type(:status) }

  let(:connection) { ActiveRecord::Base.connection }

  context 'on migration' do
    it 'can be created' do
      connection.create_enum(:status, %i(foo bar))
      expect(connection.type_exists?(:status)).to be_truthy
      expect(connection.enum_values(:status)).to eql(['foo', 'bar'])
    end

    it 'can be deleted' do
      connection.create_enum(:status, %i(foo bar))
      expect(connection.type_exists?(:status)).to be_truthy

      connection.drop_type(:status)
      expect(connection.type_exists?(:status)).to be_falsey
    end

    it 'can be renamed' do
      connection.create_enum(:status, %i(foo bar))
      connection.rename_type(:status, :new_status)
      expect(connection.type_exists?(:new_status)).to be_truthy
      expect(connection.type_exists?(:status)).to be_falsey
    end

    it 'can have prefix' do
      connection.create_enum(:status, %i(foo bar), prefix: true)
      expect(connection.enum_values(:status)).to eql(['status_foo', 'status_bar'])
    end

    it 'can have suffix' do
      connection.create_enum(:status, %i(foo bar), suffix: 'tst')
      expect(connection.enum_values(:status)).to eql(['foo_tst', 'bar_tst'])
    end

    it 'inserts values at the end' do
      connection.create_enum(:status, %i(foo bar))
      connection.add_enum_values(:status, %i(baz qux))
      expect(connection.enum_values(:status)).to eql(['foo', 'bar', 'baz', 'qux'])
    end

    it 'inserts values in the beginning' do
      connection.create_enum(:status, %i(foo bar))
      connection.add_enum_values(:status, %i(baz qux), prepend: true)
      expect(connection.enum_values(:status)).to eql(['baz', 'qux', 'foo', 'bar'])
    end

    it 'inserts values in the middle' do
      connection.create_enum(:status, %i(foo bar))
      connection.add_enum_values(:status, %i(baz), after: 'foo')
      expect(connection.enum_values(:status)).to eql(['foo', 'baz', 'bar'])

      connection.add_enum_values(:status, %i(qux), before: 'bar')
      expect(connection.enum_values(:status)).to eql(['foo', 'baz', 'qux', 'bar'])
    end

    it 'inserts values with prefix or suffix' do
      connection.create_enum(:status, %i(foo bar))
      connection.add_enum_values(:status, %i(baz), prefix: true)
      connection.add_enum_values(:status, %i(qux), suffix: 'tst')
      expect(connection.enum_values(:status)).to eql(['foo', 'bar', 'status_baz', 'qux_tst'])
    end
  end

  context 'on table definition' do
    subject { ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.new('articles') }

    it 'has the enum method' do
      expect(subject).to respond_to(:enum)
    end

    it 'can be used in a single form' do
      subject.enum('content_status')
      expect(subject['content_status'].name).to eql('content_status')
      expect(subject['content_status'].type).to eql(:content_status)
    end

    it 'can be used in a multiple form' do
      subject.enum('foo', 'bar', 'baz', subtype: :content_status)
      expect(subject['foo'].type).to eql(:content_status)
      expect(subject['bar'].type).to eql(:content_status)
      expect(subject['baz'].type).to eql(:content_status)
    end

    it 'can have custom type' do
      subject.enum('foo', subtype: :content_status)
      expect(subject['foo'].name).to eql('foo')
      expect(subject['foo'].type).to eql(:content_status)
    end

    it 'raises StatementInvalid when type isn\'t defined' do
      subject.enum('foo')
      creation = connection.schema_creation.accept subject
      expect{ connection.execute creation }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  context 'on schema' do
    it 'dumps when has it' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)
      expect(dump_io.string).to match /create_enum \"content_status\", \[/
    end

    it 'doesn\'t dump when has none' do
      connection.drop_type(:content_status, force: :cascade)

      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)
      expect(dump_io.string).not_to match /create_enum \"content_status\", \[/
    end

    it 'can be used on tables too' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)
      expect(dump_io.string).to match /t\.enum +"status", +subtype: :content_status/
    end
  end
end
