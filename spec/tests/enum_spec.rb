require 'spec_helper'

RSpec.describe 'Enum' do
  let(:connection) { ActiveRecord::Base.connection }
  let(:type_map) { Torque::PostgreSQL::Attributes::TypeMap }

  before :each do
    Torque::PostgreSQL.config.enum.base_method = :pg_enum
    Torque::PostgreSQL::Attributes::Enum.include_on(ActiveRecord::Base)

    # Define a method to find yet to define constants
    Torque::PostgreSQL.config.enum.namespace.define_singleton_method(:const_missing) do |name|
      Torque::PostgreSQL::Attributes::Enum.lookup(name)
    end

    # Define a helper method to get a sample value
    Torque::PostgreSQL.config.enum.namespace.define_singleton_method(:sample) do |name|
      Torque::PostgreSQL::Attributes::Enum.lookup(name).sample
    end
  end

  context 'on migration' do
    it 'can be created' do
      connection.create_enum(:status, %i(foo bar))
      expect(connection.type_exists?(:status)).to be_truthy
      expect(connection.enum_values(:status)).to be_eql(['foo', 'bar'])
    end

    it 'can be deleted' do
      connection.create_enum(:status, %i(foo bar))
      expect(connection.type_exists?(:status)).to be_truthy

      connection.drop_type(:status)
      expect(connection.type_exists?(:status)).to be_falsey
    end

    it 'can be renamed' do
      connection.rename_type(:content_status, :status)
      expect(connection.type_exists?(:content_status)).to be_falsey
      expect(connection.type_exists?(:status)).to be_truthy
    end

    it 'can have prefix' do
      connection.create_enum(:status, %i(foo bar), prefix: true)
      expect(connection.enum_values(:status)).to be_eql(['status_foo', 'status_bar'])
    end

    it 'can have suffix' do
      connection.create_enum(:status, %i(foo bar), suffix: 'tst')
      expect(connection.enum_values(:status)).to be_eql(['foo_tst', 'bar_tst'])
    end

    it 'inserts values at the end' do
      connection.create_enum(:status, %i(foo bar))
      connection.add_enum_values(:status, %i(baz qux))
      expect(connection.enum_values(:status)).to be_eql(['foo', 'bar', 'baz', 'qux'])
    end

    it 'inserts values in the beginning' do
      connection.create_enum(:status, %i(foo bar))
      connection.add_enum_values(:status, %i(baz qux), prepend: true)
      expect(connection.enum_values(:status)).to be_eql(['baz', 'qux', 'foo', 'bar'])
    end

    it 'inserts values in the middle' do
      connection.create_enum(:status, %i(foo bar))
      connection.add_enum_values(:status, %i(baz), after: 'foo')
      expect(connection.enum_values(:status)).to be_eql(['foo', 'baz', 'bar'])

      connection.add_enum_values(:status, %i(qux), before: 'bar')
      expect(connection.enum_values(:status)).to be_eql(['foo', 'baz', 'qux', 'bar'])
    end

    it 'inserts values with prefix or suffix' do
      connection.create_enum(:status, %i(foo bar))
      connection.add_enum_values(:status, %i(baz), prefix: true)
      connection.add_enum_values(:status, %i(qux), suffix: 'tst')
      expect(connection.enum_values(:status)).to be_eql(['foo', 'bar', 'status_baz', 'qux_tst'])
    end
  end

  context 'on table definition' do
    subject { ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.new('articles') }

    it 'has the enum method' do
      expect(subject).to respond_to(:enum)
    end

    it 'can be used in a single form' do
      subject.enum('content_status')
      expect(subject['content_status'].name).to be_eql('content_status')
      expect(subject['content_status'].type).to be_eql(:content_status)
    end

    it 'can be used in a multiple form' do
      subject.enum('foo', 'bar', 'baz', subtype: :content_status)
      expect(subject['foo'].type).to be_eql(:content_status)
      expect(subject['bar'].type).to be_eql(:content_status)
      expect(subject['baz'].type).to be_eql(:content_status)
    end

    it 'can have custom type' do
      subject.enum('foo', subtype: :content_status)
      expect(subject['foo'].name).to be_eql('foo')
      expect(subject['foo'].type).to be_eql(:content_status)
    end

    it 'raises StatementInvalid when type isn\'t defined' do
      subject.enum('foo')
      creation = connection.send(:schema_creation).accept subject
      expect{ connection.execute creation }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  context 'on schema' do
    it 'dumps when has it' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)
      expect(dump_io.string).to match /create_enum \"content_status\", \[/
    end

    it 'do not dump when has none' do
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

    it 'can have a default value as symbol' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection, dump_io)
      expect(dump_io.string).to match /t\.enum +"role", +default: :visitor, +subtype: :roles/
    end
  end

  context 'on value' do
    subject { Enum::ContentStatus }
    let(:values) { %w(created draft published archived) }
    let(:error) { Torque::PostgreSQL::Attributes::Enum::EnumError }
    let(:mock_enum) do
      klass = Class.new(subject.superclass)
      klass.instance_variable_set(:@values, values << '15')
      klass
    end

    it 'class exists' do
      namespace = Torque::PostgreSQL.config.enum.namespace
      expect(namespace.const_defined?('ContentStatus')).to be_truthy
      expect(subject < Torque::PostgreSQL::Attributes::Enum).to be_truthy
    end

    it 'lazy loads values' do
      expect(subject.instance_variable_defined?(:@values)).to be_falsey
    end

    it 'values match database values' do
      expect(subject.values).to be_eql(values)
    end

    it 'can return a sample value' do
      expect(Enum).to respond_to(:sample)
      expect(Enum::ContentStatus).to respond_to(:sample)
      expect(Enum::ContentStatus.sample).to satisfy { |v| values.include?(v) }
      expect(Enum.sample(:content_status)).to satisfy { |v| values.include?(v) }
    end

    it 'values can be iterated by using each direct on class' do
      expect(subject).to respond_to(:each)
      expect(subject.each).to be_a(Enumerator)
      expect(subject.each.entries).to be_eql(values)
    end

    it 'values can be reach using fetch, as in hash enums' do
      expect(subject).to respond_to(:fetch)

      value = subject.fetch('archived', 'archived')
      expect(value).to be_a(subject)
      expect(value).to be_eql(subject.archived)

      value = subject.fetch('other', 'other')
      expect(value).to be_nil
    end

    it 'values can be reach using [], as in hash enums' do
      expect(subject).to respond_to(:[])

      value = subject['archived']
      expect(value).to be_a(subject)
      expect(value).to be_eql(subject.archived)

      value = subject['other']
      expect(value).to be_nil
    end

    it 'accepts respond_to against value' do
      expect(subject).to respond_to(:archived)
    end

    it 'allows fast creation of values' do
      value = subject.draft
      expect(value).to be_a(subject)
    end

    it 'keeps blank values as Lazy' do
      expect(subject.new(nil)).to be_nil
      expect(subject.new([])).to be_nil
      expect(subject.new('')).to be_nil
    end

    it 'can start from nil value using lazy' do
      lazy  = Torque::PostgreSQL::Attributes::Lazy
      value = subject.new(nil)

      expect(value.__class__).to be_eql(lazy)
      expect(value.draft?).to be_falsey
      expect(value.to_s).to be_eql('')
      expect(value.to_i).to be_nil
    end

    it 'accepts values to come from numeric' do
      expect(subject.new(0)).to be_eql(subject.created)
      expect { subject.new(5) }.to raise_error(error, /out of bounds/)
    end

    it 'accepts string initialization' do
      expect(subject.new('created')).to be_eql(subject.created)
      expect { subject.new('updated') }.to raise_error(error, /not valid for/)
    end

    it 'allows values comparison' do
      value = subject.draft
      expect(value).to be > subject.created
      expect(value).to be < subject.archived
      expect(value).to be_eql(subject.draft)
      expect(value).to_not be_eql(subject.published)
      expect(subject.draft == mock_enum.draft).to be_falsey
    end

    it 'allows values comparison with string' do
      value = subject.draft
      expect(value).to be > :created
      expect(value).to be < :archived
      expect(value).to be_eql(:draft)
      expect(value).to_not be_eql(:published)
    end

    it 'allows values comparison with symbol' do
      value = subject.draft
      expect(value).to be > 'created'
      expect(value).to be < 'archived'
      expect(value).to be_eql('draft')
      expect(value).to_not be_eql('published')
    end

    it 'allows values comparison with number' do
      value = subject.draft
      expect(value).to be > 0
      expect(value).to be < 3
      expect(value).to be_eql(1)
      expect(value).to_not be_eql(2.5)
    end

    it 'does not allow cross-enum comparison' do
      expect { subject.draft < mock_enum.published }.to raise_error(error, /^Comparison/)
      expect { subject.draft > mock_enum.created }.to raise_error(error, /^Comparison/)
    end

    it 'does not allow other types comparison' do
      expect { subject.draft > true }.to raise_error(error, /^Comparison/)
      expect { subject.draft < [] }.to raise_error(error, /^Comparison/)
    end

    it 'accepts value checking' do
      value = subject.draft
      expect(value).to respond_to(:archived?)
      expect(value.draft?).to be_truthy
      expect(value.published?).to be_falsey
    end

    it 'accepts replace and bang value' do
      value = subject.draft
      expect(value).to respond_to(:archived!)
      expect(value.archived!).to be_eql(subject.archived)
      expect(value.replace('created')).to be_eql(subject.created)
    end

    it 'accepts values turn into integer by its index' do
      mock_value = mock_enum.new('15')
      expect(subject.created.to_i).to be_eql(0)
      expect(subject.archived.to_i).to be_eql(3)
      expect(mock_value.to_i).to_not be_eql(15)
      expect(mock_value.to_i).to be_eql(4)
    end

    context 'on members' do
      it 'has enumerable operations' do
        expect(subject).to respond_to(:all?)
        expect(subject).to respond_to(:any?)
        expect(subject).to respond_to(:collect)
        expect(subject).to respond_to(:count)
        expect(subject).to respond_to(:cycle)
        expect(subject).to respond_to(:detect)
        expect(subject).to respond_to(:drop)
        expect(subject).to respond_to(:drop_while)
        expect(subject).to respond_to(:each)
        expect(subject).to respond_to(:each_with_index)
        expect(subject).to respond_to(:entries)
        expect(subject).to respond_to(:find)
        expect(subject).to respond_to(:find_all)
        expect(subject).to respond_to(:find_index)
        expect(subject).to respond_to(:first)
        expect(subject).to respond_to(:flat_map)
        expect(subject).to respond_to(:include?)
        expect(subject).to respond_to(:inject)
        expect(subject).to respond_to(:lazy)
        expect(subject).to respond_to(:map)
        expect(subject).to respond_to(:member?)
        expect(subject).to respond_to(:one?)
        expect(subject).to respond_to(:reduce)
        expect(subject).to respond_to(:reject)
        expect(subject).to respond_to(:reverse_each)
        expect(subject).to respond_to(:select)
        expect(subject).to respond_to(:sort)
        expect(subject).to respond_to(:zip)
      end

      it 'works with map' do
        result = subject.map(&:to_i)
        expect(result).to be_eql([0, 1, 2, 3])
      end
    end
  end

  context 'on OID' do
    let(:enum) { Enum::ContentStatus }
    subject { Torque::PostgreSQL::Adapter::OID::Enum.new('content_status') }

    context 'on deserialize' do
      it 'returns nil' do
        expect(subject.deserialize(nil)).to be_nil
      end

      it 'returns enum' do
        value = subject.deserialize('created')
        expect(value).to be_a(enum)
        expect(value).to be_eql(enum.created)
      end
    end

    context 'on serialize' do
      it 'returns nil' do
        expect(subject.serialize(nil)).to be_nil
        expect(subject.serialize('test')).to be_nil
        expect(subject.serialize(15)).to be_nil
      end

      it 'returns as string' do
        expect(subject.serialize(enum.created)).to be_eql('created')
        expect(subject.serialize(1)).to be_eql('draft')
      end
    end

    context 'on cast' do
      it 'accepts nil' do
        expect(subject.cast(nil)).to be_nil
      end

      it 'accepts invalid values as nil' do
        expect(subject.cast(false)).to be_nil
        expect(subject.cast(true)).to be_nil
        expect(subject.cast([])).to be_nil
      end

      it 'accepts string' do
        value = subject.cast('created')
        expect(value).to be_eql(enum.created)
        expect(value).to be_a(enum)
      end

      it 'accepts numeric' do
        value = subject.cast(1)
        expect(value).to be_eql(enum.draft)
        expect(value).to be_a(enum)
      end
    end
  end

  context 'on I18n' do
    subject { Enum::ContentStatus }

    it 'has the text method' do
      expect(subject.new(0)).to respond_to(:text)
    end

    it 'brings the correct values' do
      expect(subject.new(0).text).to be_eql('1 - Created')
      expect(subject.new(1).text).to be_eql('Draft (2)')
      expect(subject.new(2).text).to be_eql('Finally published')
      expect(subject.new(3).text).to be_eql('Archived')
    end
  end

  context 'on uninitialized model' do
    before(:each) { Torque::PostgreSQL.config.enum.initializer = true }
    subject do
      APost = Class.new(ActiveRecord::Base)
      APost.table_name = 'posts'
      APost
    end

    it 'has no statuses method' do
      expect(subject).to_not respond_to(:statuses)
    end

    it 'can load statuses on the fly' do
      result = subject.statuses
      expect(result).to be_a(Array)
      expect(result).to be_eql(Enum::ContentStatus.values)
    end
  end

  context 'on model' do
    before(:each) { type_map.decorate!(User, :role) }

    subject { User }
    let(:instance) { FactoryGirl.build(:user) }

    it 'has all enum methods' do
      expect(subject).to  respond_to(:roles)
      expect(subject).to  respond_to(:roles_texts)
      expect(subject).to  respond_to(:roles_options)
      expect(instance).to respond_to(:role_text)

      subject.roles.each do |value|
        expect(subject).to  respond_to(value)
        expect(instance).to respond_to(value + '?')
        expect(instance).to respond_to(value + '!')
      end
    end

    it 'plural method brings the list of values' do
      result = subject.roles
      expect(result).to be_a(Array)
      expect(result).to be_eql(Enum::Roles.values)
    end

    it 'text value now uses model and attribute references' do
      instance.role = :visitor
      expect(instance.role_text).to be_eql('A simple Visitor')

      instance.role = :assistant
      expect(instance.role_text).to be_eql('An Assistant')

      instance.role = :manager
      expect(instance.role_text).to be_eql('The Manager')

      instance.role = :admin
      expect(instance.role_text).to be_eql('Super Duper Admin')
    end

    it 'has scopes correctly applied' do
      subject.roles.each do |value|
        expect(subject.send(value).to_sql).to match(/WHERE "users"."role" = '#{value}'/)
      end
    end

    it 'has scopes available on associations' do
      author = FactoryGirl.create(:author)
      FactoryGirl.create(:post, author: author)

      type_map.decorate!(Post, :status)
      expect(author.posts).to respond_to(:test_scope)

      Enum::ContentStatus.each do |value|
        expect(author.posts).to be_a(ActiveRecord::Associations::CollectionProxy)
        expect(author.posts).to respond_to(value.to_sym)
        expect(author.posts.send(value).to_sql).to match(/AND "posts"."status" = '#{value}'/)
      end
    end

    it 'ask methods work' do
      instance.role = :assistant
      expect(instance.manager?).to be_falsey
      expect(instance.assistant?).to be_truthy
    end

    it 'bang methods work' do
      instance.admin!
      expect(instance.persisted?).to be_truthy

      updated_at = instance.updated_at
      subject.enum_save_on_bang = false
      instance.visitor!

      expect(instance.role).to be_eql(:visitor)
      expect(instance.updated_at).to be_eql(updated_at)

      instance.reload
      expect(instance.role).to be_eql(:admin)
    end

    it 'raises when starting an enum with conflicting methods' do
      AText = Class.new(ActiveRecord::Base)
      AText.table_name = 'texts'

      expect { type_map.decorate!(AText, :conflict) }.to raise_error(ArgumentError, /already exists in/)
    end

    context 'without autoload' do
      subject { Author }
      let(:instance) { FactoryGirl.build(:author) }

      it 'configurating an enum should not invoke a query' do
        klass = Torque::PostgreSQL::Adapter::SchemaStatements
        expect_any_instance_of(klass).to_not receive(:enum_values).with('types')
        Activity.pg_enum :type
        expect(Activity.defined_enums).to_not include('type')
      end

      it 'has both rails original enum and the new pg_enum' do
        expect(subject).to respond_to(:enum)
        expect(subject).to respond_to(:pg_enum)
        expect(subject.method(:pg_enum).arity).to eql(-1)
      end

      it 'does not create all methods' do
        AAuthor = Class.new(ActiveRecord::Base)
        AAuthor.table_name = 'authors'

        expect(AAuthor).to_not respond_to(:specialties)
        expect(AAuthor).to_not respond_to(:specialties_texts)
        expect(AAuthor).to_not respond_to(:specialties_options)
        expect(AAuthor.instance_methods).to_not include(:specialty_text)

        Enum::Specialties.values.each do |value|
          expect(AAuthor).to_not respond_to(value)
          expect(AAuthor.instance_methods).to_not include(value + '?')
          expect(AAuthor.instance_methods).to_not include(value + '!')
        end
      end

      it 'can be manually initiated' do
        type_map.decorate!(Author, :specialty)
        expect(subject).to  respond_to(:specialties)
        expect(subject).to  respond_to(:specialties_texts)
        expect(subject).to  respond_to(:specialties_options)
        expect(instance).to respond_to(:specialty_text)

        Enum::Specialties.values.each do |value|
          expect(subject).to  respond_to(value)
          expect(instance).to respond_to(value + '?')
          expect(instance).to respond_to(value + '!')
        end
      end
    end

    context 'with prefix' do
      before(:each) { type_map.decorate!(Author, :specialty, prefix: 'in') }
      subject { Author }
      let(:instance) { FactoryGirl.build(:author) }

      it 'creates all methods correctly' do
        expect(subject).to  respond_to(:specialties)
        expect(subject).to  respond_to(:specialties_texts)
        expect(subject).to  respond_to(:specialties_options)
        expect(instance).to respond_to(:specialty_text)

        subject.specialties.each do |value|
          expect(subject).to  respond_to('in_' + value)
          expect(instance).to respond_to('in_' + value + '?')
          expect(instance).to respond_to('in_' + value + '!')
        end
      end
    end

    context 'with suffix, only, and except' do
      before(:each) do
        type_map.decorate!(Author, :specialty, suffix: 'expert', only: %w(books movies),
          except: 'books')
      end

      subject { Author }
      let(:instance) { FactoryGirl.build(:author) }

      it 'creates only the requested methods' do
        expect(subject).to  respond_to('movies_expert')
        expect(instance).to respond_to('movies_expert?')
        expect(instance).to respond_to('movies_expert!')

        expect(subject).to_not  respond_to('books_expert')
        expect(instance).to_not respond_to('books_expert?')
        expect(instance).to_not respond_to('books_expert!')

        expect(subject).to_not  respond_to('plays_expert')
        expect(instance).to_not respond_to('plays_expert?')
        expect(instance).to_not respond_to('plays_expert!')

      end
    end
  end
end
