require 'spec_helper'

RSpec.describe 'LTree' do
  let(:table_definition) { ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition }
  let(:connection) { ActiveRecord::Base.connection }
  let(:source) { ActiveRecord::Base.connection_pool }

  let(:ltree) { Torque::PostgreSQL::LTree }
  let(:lquery) { Torque::PostgreSQL::LQuery }

  context 'on table definition' do
    subject { table_definition.new(connection, 'articles') }

    it 'has the ltree method' do
      expect(subject).to respond_to(:ltree)
    end

    it 'has the lquery method' do
      expect(subject).to respond_to(:lquery)
    end

    it 'can define an ltree column' do
      subject.ltree('path')
      expect(subject['path'].name).to eql('path')
      expect(subject['path'].type).to eql(:ltree)
    end

    it 'can define an lquery column' do
      subject.lquery('pattern')
      expect(subject['pattern'].name).to eql('pattern')
      expect(subject['pattern'].type).to eql(:lquery)
    end

    it 'can define an array of paths' do
      subject.ltree('permissions', array: true)
      expect(subject['permissions'].type).to eql(:ltree)
      expect(subject['permissions'].options[:array]).to be_truthy
    end

    it 'requires a column name' do
      expect { subject.ltree }.to raise_error(ArgumentError, /Missing column name/)
      expect { subject.lquery }.to raise_error(ArgumentError, /Missing column name/)
    end
  end

  context 'on schema' do
    it 'dumps the column as an ltree' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(source, dump_io)
      expect(dump_io.string).to match(/t\.ltree +"path"/)
    end

    it 'dumps an array of paths' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(source, dump_io)
      expect(dump_io.string).to match(/t\.ltree +"permissions", array: true/)
    end

    it 'is a valid type' do
      expect(connection.valid_type?(:ltree)).to be_truthy
      expect(connection.valid_type?(:lquery)).to be_truthy
    end
  end

  context 'on the path' do
    it 'is an array of labels' do
      expect(ltree.new('Top.Science')).to be_a(Array)
      expect(ltree.new('Top.Science')).to be_eql(%w[Top Science])
    end

    it 'accepts a string, an array or symbols' do
      expect(ltree.new('Top.Science').to_s).to be_eql('Top.Science')
      expect(ltree.new(%w[Top Science]).to_s).to be_eql('Top.Science')
      expect(ltree[:Top, :Science].to_s).to be_eql('Top.Science')
    end

    it 'knows its depth' do
      expect(ltree.new('a.b.c').depth).to be_eql(3)
      expect(ltree.new('').depth).to be_eql(0)
    end

    it 'knows its root' do
      expect(ltree.new('a.b.c').root.to_s).to be_eql('a')
      expect(ltree.new('a.b.c').root?).to be_falsey
      expect(ltree.new('a').root?).to be_truthy
    end

    it 'has no parent when it is a root' do
      expect(ltree.new('a.b.c').parent.to_s).to be_eql('a.b')
      expect(ltree.new('a').parent).to be_nil
      expect(ltree.new('').parent).to be_nil
    end

    it 'can be extended' do
      expect((ltree.new('a.b') / 'c').to_s).to be_eql('a.b.c')
      expect((ltree.new('a.b') + %w[c d]).to_s).to be_eql('a.b.c.d')
      expect(ltree.new('a.b') / 'c').to be_a(ltree)
    end

    it 'checks ancestors and descendants, including itself' do
      expect(ltree.new('a.b').ancestor_of?('a.b.c')).to be_truthy
      expect(ltree.new('a.b').ancestor_of?('a.b')).to be_truthy
      expect(ltree.new('a.b').ancestor_of?('a.c')).to be_falsey
      expect(ltree.new('a.b.c').descendant_of?('a.b')).to be_truthy
      expect(ltree.new('a.b').descendant_of?('a.b.c')).to be_falsey
    end

    it 'aliases the checks as covering' do
      expect(ltree.new('a.b').covers?('a.b.c')).to be_truthy
      expect(ltree.new('a.b.c').covered_by?('a.b')).to be_truthy
    end

    it 'finds the longest common ancestor' do
      expect(ltree.new('1.2.3').lca('1.2.3.4.5.6').to_s).to be_eql('1.2')
      expect(ltree.new('1.2.2.3').lca('1.2.3.4.5.6').to_s).to be_eql('1.2')
      expect(ltree.new('a.b').lca('a.b').to_s).to be_eql('a')
      expect(ltree.new('a.b').lca('c.d').to_s).to be_eql('')
    end

    it 'finds the position of a subpath' do
      subject = ltree.new('0.1.2.3.5.4.5.6.8.5.6.8')
      expect(subject.index_of('5.6')).to be_eql(6)
      expect(subject.index_of('5.6', -4)).to be_eql(9)
      expect(subject.index_of('9.9')).to be_eql(-1)
    end

    it 'rejects anything that is not a plain sequence of labels' do
      expect { ltree.new('a.*') }.to raise_error(ArgumentError, /not a valid ltree label/)
      expect { ltree.new('a b') }.to raise_error(ArgumentError, /not a valid ltree label/)
      expect { ltree.new(['a', %w[b c]]) }.to raise_error(ArgumentError, /only make sense on an lquery/)
      expect { ltree.new(['a', 1..2]) }.to raise_error(ArgumentError, /only make sense on an lquery/)
    end
  end

  context 'on the pattern' do
    samples = {
      'a label'              => [%w[Top], 'Top'],
      'a symbol label'       => [[:Top], 'Top'],
      'a star'               => [['Top', :any], 'Top.*'],
      'an exact quantifier'  => [['Top', 2..2], 'Top.*{2}'],
      'a range quantifier'   => [['Top', 0..2], 'Top.*{0,2}'],
      'an open quantifier'   => [['Top', 1..], 'Top.*{1,}'],
      'a closed quantifier'  => [['Top', ..3], 'Top.*{,3}'],
      'an exclusive range'   => [['Top', 2...4], 'Top.*{2,3}'],
      'a prefix modifier'    => [['sport*'], 'sport*'],
      'a case modifier'      => [['sport@'], 'sport@'],
      'a word modifier'      => [['sport%'], 'sport%'],
      'combined modifiers'   => [['sport*@'], 'sport*@'],
      'alternatives'         => [[%w[football tennis]], 'football|tennis'],
      'a negated group'      => [['!football|tennis'], '!football|tennis'],
      'a quantified item'    => [['football{1,}'], 'football{1,}'],
    }

    samples.each do |title, (input, expected)|
      it "compiles #{title}" do
        expect(Torque::PostgreSQL::LQuery.new(input).to_s).to be_eql(expected)
      end
    end

    it 'compiles the example from the PostgreSQL manual' do
      subject = lquery['Top', 0..2, 'sport*@', '!football|tennis{1,}', %w[Russ* Spain]]
      expect(subject.to_s).to be_eql('Top.*{0,2}.sport*@.!football|tennis{1,}.Russ*|Spain')
    end

    it 'accepts its own text form' do
      expect(lquery.new('Top.*.sport*@').to_s).to be_eql('Top.*.sport*@')
    end

    it 'compares by its text form' do
      expect(lquery['Top', :any]).to be_eql(lquery.new('Top.*'))
      expect(lquery['Top', :any].hash).to be_eql(lquery.new('Top.*').hash)
    end

    it 'rejects items that are not valid' do
      expect { lquery['a.b'] }.to raise_error(ArgumentError, /not a valid lquery item/)
      expect { lquery['foo{'] }.to raise_error(ArgumentError, /not a valid lquery item/)
      expect { lquery['a b'] }.to raise_error(ArgumentError, /not a valid lquery item/)
      expect { lquery[{ a: 1 }] }.to raise_error(ArgumentError, /Unable to use/)
    end

    it 'rejects quantifiers that make no sense' do
      expect { lquery[2..0] }.to raise_error(ArgumentError, /not a valid quantifier/)
      expect { lquery[-1..2] }.to raise_error(ArgumentError, /not a valid quantifier/)
    end

    it 'rejects an empty alternation' do
      expect { lquery[[]] }.to raise_error(ArgumentError, /at least one label/)
    end
  end

  context 'on records' do
    let(:root) { Category.create!(title: 'Top') }
    let(:child) { Category.create!(title: 'Science') }

    it 'uses the primary key as the label' do
      expect(ltree.new(root).to_s).to be_eql(root.id.to_s)
      expect(ltree[root, child].to_s).to be_eql("#{root.id}.#{child.id}")
    end

    it 'mixes records with plain labels' do
      expect(ltree.new(['app', root]).to_s).to be_eql("app.#{root.id}")
    end

    it 'extends a path with a record' do
      expect((ltree.new('app') / child).to_s).to be_eql("app.#{child.id}")
      expect((ltree.new('app') + [root, child]).to_s).to be_eql("app.#{root.id}.#{child.id}")
    end

    it 'compares paths given as records' do
      subject = ltree[root, child]
      expect(ltree.new(root).ancestor_of?(subject)).to be_truthy
      expect(subject.descendant_of?(root)).to be_truthy
      expect(subject.covered_by?(ltree.new(root))).to be_truthy
    end

    it 'accepts records on the remaining path operations' do
      subject = ltree[root, child]
      expect(subject.lca(ltree[root, child]).to_s).to be_eql(root.id.to_s)
      expect(subject.index_of(child)).to be_eql(1)
    end

    it 'uses the primary key on a pattern' do
      expect(lquery[root, :any].to_s).to be_eql("#{root.id}.*")
      expect(lquery[[root, child]].to_s).to be_eql("#{root.id}|#{child.id}")
    end

    it 'follows a custom primary key' do
      klass = Class.new(Category) do
        self.table_name = 'categories'
        self.primary_key = 'title'
      end

      expect(ltree.new(klass.find(root.title)).to_s).to be_eql('Top')
    end

    it 'refuses a record that was never saved' do
      expect { ltree.new(Category.new) }
        .to raise_error(ArgumentError, /its id is still empty/)
    end

    it 'writes a record-based path to the database' do
      record = Category.create!(title: 'Astronomy', path: [root, child])
      expect(Category.find(record.id).path).to be_eql([root.id.to_s, child.id.to_s])
    end

    it 'queries with a record-based path' do
      Category.create!(title: 'Astronomy', path: [root, child])

      expect(Category.where(path: [root, child]).count).to be_eql(1)
      expect(Category.where(path: [root, :any]).count).to be_eql(1)
    end

    it 'takes a lone record as a single-label path' do
      Category.create!(title: 'Only', path: [root])

      expect(Category.where(path: root).to_sql)
        .to include(%[WHERE "categories"."path" = '#{root.id}'])
      expect(Category.where(path: root).count).to be_eql(1)
    end

    it 'reaches the entries of an array column' do
      user = User.create!(name: 'Rick', permissions: [root, [root, child]])
      expect(User.find(user.id).permissions)
        .to be_eql([[root.id.to_s], [root.id.to_s, child.id.to_s]])
    end
  end

  context 'on compatible objects' do
    let(:path_like) { ::Struct.new(:to_tree_path) }

    after { Torque::PostgreSQL.config.ltree.compatible_method = :to_tree_path }

    it 'takes over as a path' do
      expect(ltree.new(path_like.new('app.users')).to_s).to be_eql('app.users')
      expect(ltree.new(path_like.new(%w[app users])).to_s).to be_eql('app.users')
    end

    it 'can be one entry among labels' do
      subject = ltree.new(['top', path_like.new('app.users')])
      expect(subject.to_s).to be_eql('top.app.users')
    end

    it 'is accepted while comparing two paths' do
      other = path_like.new('app.users')
      expect(ltree.new('app').ancestor_of?(other)).to be_truthy
      expect(ltree.new('app.users.write').descendant_of?(other)).to be_truthy
      expect(ltree.new('app.users.write').index_of(other)).to be_eql(0)
    end

    it 'is accepted while extending a path' do
      expect((ltree.new('top') / path_like.new('app.users')).to_s).to be_eql('top.app.users')
    end

    it 'contributes every label of a pattern' do
      expect(lquery[path_like.new('app.users'), :any].to_s).to be_eql('app.users.*')
    end

    it 'turns the condition into a match when it describes a pattern' do
      expect(Category.where(path: path_like.new('app.*')).to_sql)
        .to include(%[WHERE "categories"."path" ~ 'app.*'::lquery])
    end

    it 'keeps the condition an equality when it describes a path' do
      expect(Category.where(path: path_like.new('app.users')).to_sql)
        .to include(%[WHERE "categories"."path" = 'app.users'])
    end

    it 'wins over the primary key of a record' do
      klass = Class.new(Category)
      klass.define_method(:to_tree_path) { "cat.#{title}" }
      record = klass.create!(title: 'Science')

      expect(ltree.new(record).to_s).to be_eql('cat.Science')
      expect(Category.where(path: record).to_sql)
        .to include(%[WHERE "categories"."path" = 'cat.Science'])
    end

    it 'is ignored when the config has no method' do
      Torque::PostgreSQL.config.ltree.compatible_method = nil
      expect { ltree.new(path_like.new('app.users')) }
        .to raise_error(ArgumentError, /only make sense on an lquery/)
    end
  end

  context 'on markers' do
    it 'treats a plain path as a path' do
      expect(lquery.marker?('Top.Science')).to be_falsey
      expect(lquery.marker?(%w[Top Science])).to be_falsey
      expect(lquery.marker?(%i[Top Science])).to be_falsey
    end

    it 'treats anything with a query feature as a pattern' do
      expect(lquery.marker?(['Top', :any])).to be_truthy
      expect(lquery.marker?(['Top', 1..])).to be_truthy
      expect(lquery.marker?(['Top', %w[a b]])).to be_truthy
      expect(lquery.marker?('Top.*')).to be_truthy
      expect(lquery.marker?('!Top')).to be_truthy
      expect(lquery.marker?('Top@')).to be_truthy
    end
  end

  context 'on sanitize' do
    after { Torque::PostgreSQL.config.ltree.sanitize = nil }

    it 'does nothing by default' do
      expect(ltree.new('a-b').to_s).to be_eql('a-b')
    end

    it 'replaces the configured characters on a path' do
      Torque::PostgreSQL.config.ltree.sanitize = { '-' => '_' }
      expect(ltree.new('a-b.c-d').to_s).to be_eql('a_b.c_d')
    end

    it 'can drop characters entirely' do
      Torque::PostgreSQL.config.ltree.sanitize = { '-' => '' }
      expect(ltree.new('a-b').to_s).to be_eql('ab')
    end

    it 'reaches the labels of a pattern' do
      Torque::PostgreSQL.config.ltree.sanitize = { '-' => '_' }
      expect(lquery['a-b*', %w[c-d e]].to_s).to be_eql('a_b*.c_d|e')
    end

    it 'never rewrites a quantifier' do
      Torque::PostgreSQL.config.ltree.sanitize = { '1' => '9' }
      expect(lquery['foo{1,2}'].to_s).to be_eql('foo{1,2}')
    end

    it 'does not apply to values read from the database' do
      Torque::PostgreSQL.config.ltree.sanitize = { 'a' => 'z' }
      expect(ltree.load('a.b').to_s).to be_eql('a.b')
    end
  end

  context 'on OID' do
    subject { Torque::PostgreSQL::Adapter::OID::Ltree.new }

    it 'has the right type' do
      expect(subject.type).to be_eql(:ltree)
    end

    it 'deserializes into a path' do
      expect(subject.deserialize('Top.Science')).to be_a(Torque::PostgreSQL::LTree)
      expect(subject.deserialize('Top.Science')).to be_eql(%w[Top Science])
      expect(subject.deserialize(nil)).to be_nil
    end

    it 'serializes back into text' do
      expect(subject.serialize(%w[Top Science])).to be_eql('Top.Science')
      expect(subject.serialize('Top.Science')).to be_eql('Top.Science')
      expect(subject.serialize(nil)).to be_nil
      expect(subject.serialize('')).to be_nil
    end

    it 'validates on the way in' do
      expect { subject.serialize('Top.*') }.to raise_error(ArgumentError)
    end
  end

  context 'on the model' do
    subject { Category.new }

    it 'reads and writes a path' do
      subject.path = 'Top.Science'
      expect(subject.path).to be_a(Torque::PostgreSQL::LTree)
      expect(subject.path).to be_eql(%w[Top Science])
    end

    it 'accepts an array of labels' do
      subject.path = %w[Top Science]
      expect(subject.path.to_s).to be_eql('Top.Science')
    end

    it 'round trips through the database' do
      subject.update!(title: 'Science', path: 'Top.Science')
      expect(Category.find(subject.id).path).to be_eql(%w[Top Science])
    end

    it 'round trips an array of paths as an array of arrays' do
      user = User.create!(name: 'Rick', permissions: ['app.users.write', %w[app posts]])
      reloaded = User.find(user.id)

      expect(reloaded.permissions).to be_eql([%w[app users write], %w[app posts]])
      expect(reloaded.permissions.first).to be_a(Torque::PostgreSQL::LTree)
    end

    it 'refuses a pattern where a path is expected' do
      subject.path = 'Top.*'
      expect { subject.path }.to raise_error(ArgumentError, /not a valid ltree label/)
    end
  end

  context 'on predicate builder' do
    subject { Category.all }

    it 'uses equality for a plain path' do
      expect(subject.where(path: 'Top.Science').to_sql)
        .to include(%[WHERE "categories"."path" = 'Top.Science'])
    end

    it 'uses equality for a plain array of labels' do
      expect(subject.where(path: %w[Top Science]).to_sql)
        .to include(%[WHERE "categories"."path" = 'Top.Science'])
    end

    it 'matches a pattern when the value has a star' do
      expect(subject.where(path: ['Top', :any]).to_sql)
        .to include(%[WHERE "categories"."path" ~ 'Top.*'::lquery])
    end

    it 'matches a pattern when the value has a quantifier' do
      expect(subject.where(path: ['Top', 1..]).to_sql)
        .to include(%[WHERE "categories"."path" ~ 'Top.*{1,}'::lquery])
    end

    it 'matches a pattern when the value has alternatives' do
      expect(subject.where(path: ['Top', %w[a b]]).to_sql)
        .to include(%[WHERE "categories"."path" ~ 'Top.a|b'::lquery])
    end

    it 'matches a pattern written as a string' do
      expect(subject.where(path: 'Top.*.sport*@').to_sql)
        .to include(%[WHERE "categories"."path" ~ 'Top.*.sport*@'::lquery])
    end

    it 'accepts a pattern object' do
      expect(subject.where(path: lquery['Top', :any]).to_sql)
        .to include(%[WHERE "categories"."path" ~ 'Top.*'::lquery])
    end

    it 'finds the records that match' do
      Category.create!(title: 'Science', path: 'Top.Science')
      Category.create!(title: 'Astronomy', path: 'Top.Science.Astronomy')
      Category.create!(title: 'Hobbies', path: 'Top.Hobbies')

      expect(Category.where(path: ['Top', :any]).count).to be_eql(3)
      expect(Category.where(path: %w[Top Science]).count).to be_eql(1)
      expect(Category.where(path: ['Top', 'Science', :any]).count).to be_eql(2)
    end

    it 'leaves an array column to the default behavior' do
      expect(User.where(permissions: ['app.users']).to_sql)
        .to include(%[WHERE "users"."permissions" = ])
    end

    it 'never takes an array as a list of values' do
      expect(subject.where(path: %w[Top Science]).to_sql).not_to include('IN')
    end
  end

  context 'on arel' do
    let(:attribute) { Category.arel_table['path'] }

    it 'has the tree operators' do
      expect(attribute).to respond_to(:contains)
      expect(attribute).to respond_to(:contained_by)
      expect(attribute).to respond_to(:matches_lquery)
      expect(attribute).to respond_to(:matches_any_lquery)
    end

    it 'builds an ancestor condition' do
      sql = Category.where(attribute.contains(::Arel.sql("'Top.Science'"))).to_sql
      expect(sql).to include(%["categories"."path" @> 'Top.Science'])
    end

    it 'builds a pattern condition' do
      value = ::Arel.sql("'Top.*'").pg_cast('lquery')
      sql = Category.where(attribute.matches_lquery(value)).to_sql
      expect(sql).to include(%["categories"."path" ~ 'Top.*'::lquery])
    end

    it 'builds a condition against many patterns' do
      value = ::Arel.array(['Top.*', 'Other.*'], cast: 'lquery')
      sql = Category.where(attribute.matches_any_lquery(value)).to_sql
      expect(sql).to include(%["categories"."path" ? ARRAY['Top.*', 'Other.*']::lquery[]])
    end
  end

  context 'on authorization' do
    let(:required) { Torque::PostgreSQL::LTree.new('app.users.write') }
    let(:grants) { User.arel_table['permissions'] }

    before do
      User.create!(name: 'Admin', permissions: ['app'])
      User.create!(name: 'Editor', permissions: ['app.posts', 'app.users'])
      User.create!(name: 'Guest', permissions: ['app.posts'])
    end

    it 'finds the users a grant covers, in SQL' do
      condition = grants.contains(Torque::PostgreSQL::FN.bind_type(required.to_s, cast: 'ltree'))
      names = User.where(condition).pluck(:name)

      expect(names).to match_array(%w[Admin Editor])
    end

    it 'agrees with the same check performed in Ruby' do
      condition = grants.contains(Torque::PostgreSQL::FN.bind_type(required.to_s, cast: 'ltree'))
      from_sql = User.where(condition).pluck(:name)

      in_memory = User.all.select do |user|
        user.permissions.any? { |grant| grant.covers?(required) }
      end

      expect(from_sql).to match_array(in_memory.map(&:name))
    end

    it 'matches grants against a pattern' do
      condition = grants.matches_lquery(::Arel.sql("'app.users.*'").pg_cast('lquery'))
      expect(User.where(condition).pluck(:name)).to match_array(%w[Editor])
    end
  end
end
