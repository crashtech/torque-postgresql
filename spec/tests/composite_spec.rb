require 'spec_helper'

RSpec.describe 'Composite Type', type: :feature do
  let(:connection) { ActiveRecord::Base.connection }

  context 'on migration' do
    it 'can be created' do
      connection.create_composite_type(:address) { |t| t.string :street }
      columns = connection.composite_columns(:address)

      expect(connection.type_exists?(:address)).to be_truthy
      expect(columns.length).to eql(1)
      expect(columns.first.name).to eql('street')
      expect(columns.first.type).to eql(:string)
    end

    it 'can be deleted' do
      connection.create_enum(:address, %i(foo bar))
      expect(connection.type_exists?(:address)).to be_truthy

      connection.drop_type(:address)
      expect(connection.type_exists?(:address)).to be_falsey
    end

    it 'can be renamed' do
      connection.rename_type(:published, :new_published)
      expect(connection.type_exists?(:new_published)).to be_truthy
      expect(connection.type_exists?(:published)).to be_falsey
    end
  end

  context 'on table definition' do
    subject { ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.new('articles') }

    it 'has the composite method' do
      expect(subject).to respond_to(:composite)
    end

    it 'can be used in a single form' do
      subject.composite('published')
      expect(subject['published'].name).to eql('published')
      expect(subject['published'].type).to eql(:published)
    end

    it 'can be used in a multiple form' do
      subject.composite('foo', 'bar', 'baz', subtype: :published)
      expect(subject['foo'].type).to eql(:published)
      expect(subject['bar'].type).to eql(:published)
      expect(subject['baz'].type).to eql(:published)
    end

    it 'can have custom type' do
      subject.composite('foo', subtype: :published)
      expect(subject['foo'].name).to eql('foo')
      expect(subject['foo'].type).to eql(:published)
    end

    it 'raises StatementInvalid when type isn\'t defined' do
      subject.composite('foo')
      creation = connection.schema_creation.accept subject
      expect{ connection.execute creation }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  context 'on schema' do
    it 'dumps when has it' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)
      expect(dump_io.string).to match /create_composite_type \"published\",/
    end

    it 'doesn\'t dump when has none' do
      connection.drop_type(:published, force: :cascade)

      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)
      expect(dump_io.string).not_to match /create_composite_type \"published\",/
    end

    it 'can be used on tables too' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)
      expect(dump_io.string).to match /t\.composite +"published", +subtype: :published/
    end
  end

  xcontext 'on model' do
    let(:simple) { Post.new }
    let(:filled) { FactoryGirl.create(:post, published: [1, Time.now.utc, 'URL', true]) }
    let(:type_class) { Torque::PostgreSQL::Attributes::Composite::Base }

    it 'published attribute starts with the correct value' do
      expect(simple.published).to be_a(type_class)
    end

    it 'published attribute has the correct format' do
      expect(filled.published).to be_a(type_class)
      expect(filled.published.status).to be_truthy
      expect(filled.published.url).to be_eql('URL')
      expect(filled.published.user_id).to be_eql(1)
    end

    it 'respect model changed identification' do
      expect(filled.published.status).to be_truthy
      expect(filled.changed?).to be_falsey
      filled.published.status = false
      expect(filled.changed?).to be_truthy
      expect(filled.published.status).to be_falsey
    end

    it 'works on changing and saving' do
      filled.published.url = 'NEW URL'
      expect(filled.save!).to be_truthy

      filled.reload
      expect(filled.published.url).to be_eql('NEW URL')
    end

    it 'works with quoutes' do
      filled.published.url = 'Quoutes test "\''
      expect(filled.save!).to be_truthy

      filled.reload
      expect(filled.published.url).to be_eql('Quoutes test "\'')
    end

  end
end
