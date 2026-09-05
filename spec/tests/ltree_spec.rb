require 'spec_helper'

RSpec.describe 'LTree' do
  let(:table_definition) { ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition }
  let(:connection) { ActiveRecord::Base.connection }
  let(:source) { ActiveRecord::Base.connection_pool }

  let(:ltree) { Torque::PostgreSQL::LTree }
  let(:lquery) { Torque::PostgreSQL::LQuery }
  let(:ltree_type) { Torque::PostgreSQL::Adapter::OID::Ltree.new }
  let(:lquery_type) { Torque::PostgreSQL::Adapter::OID::Lquery.new }

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

    it 'dumps the column as an lquery' do
      dump_io = StringIO.new
      ActiveRecord::SchemaDumper.dump(source, dump_io)
      expect(dump_io.string).to match(/t\.lquery +"pattern"/)
      expect(dump_io.string).to match(/t\.lquery +"patterns", array: true/)
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
    it 'enumerates its labels' do
      subject = ltree.new('Top.Science')
      expect(subject).to be_a(Enumerable)
      expect(subject.items).to be_eql(%w[Top Science])
      expect(subject.to_a).to be_eql(%w[Top Science])
      expect(subject.map(&:downcase)).to be_eql(%w[top science])
    end

    it 'compares with a plain array' do
      expect(ltree.new('Top.Science')).to be_eql(%w[Top Science])
      expect(ltree.new('Top.Science')).to be_eql(ltree[:Top, :Science])
      expect(ltree.new('Top.Science')).not_to be_eql(%w[Top])
      expect(ltree.new('Top.Science').hash).to be_eql(ltree[:Top, :Science].hash)
    end

    it 'accepts a string, an array or symbols' do
      expect(ltree.new('Top.Science').to_s).to be_eql('Top.Science')
      expect(ltree.new(%w[Top Science]).to_s).to be_eql('Top.Science')
      expect(ltree[:Top, :Science].to_s).to be_eql('Top.Science')
    end

    it 'flattens nested arrays into labels' do
      expect(ltree.new(['Top', %w[Science Astro]]).to_s).to be_eql('Top.Science.Astro')
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

    it 'holds the pure items' do
      expect(lquery['Top', :any].items).to be_eql(['Top', :any])
      expect(lquery.new('Top.*{1,2}.a|b').items).to be_eql(['Top', 1..2, %w[a b]])
      expect(lquery.new('Top.*').to_a).to be_eql(['Top', :any])
    end

    it 'enumerates its items' do
      expect(lquery['Top', :any]).to be_a(Enumerable)
      expect(lquery['Top', :any].map(&:to_s)).to be_eql(%w[Top any])
    end

    it 'accepts its own text form' do
      expect(lquery.new('Top.*.sport*@').items).to be_eql(['Top', :any, 'sport*@'])
      expect(lquery.new('Top.*.sport*@').to_s).to be_eql('Top.*.sport*@')
    end

    it 'compares by its items' do
      expect(lquery['Top', :any]).to be_eql(lquery.new('Top.*'))
      expect(lquery['Top', :any]).to be_eql(['Top', :any])
      expect(lquery['Top', :any].hash).to be_eql(lquery.new('Top.*').hash)
    end

    it 'leaves the validation to the database' do
      expect(lquery['a b'].to_s).to be_eql('a b')
      expect(lquery[2..0].to_s).to be_eql('*{2,0}')
      expect { Category.where(path: ['a b']).count }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  context 'on matching' do
    let(:root) { Category.create!(title: 'Top') }

    after { Torque::PostgreSQL.config.ltree.sanitize = nil }

    it 'compiles into a regular expression over the text of a path' do
      subject = lquery.new('Top.*{1,}.sport*@')
      expect(subject.pattern).to be_a(Regexp)
      expect(subject.pattern).to be_equal(subject.pattern)
      expect(subject.pattern).to match('Top.Science.Sports')
      expect(subject.pattern).not_to match('Top.Sports')
      expect(subject.pattern).not_to match('Other.Top.Science.Sports')
    end

    it 'matches a string, an array or a path' do
      subject = lquery['Top', :any]
      expect(subject.match?('Top.Science')).to be_truthy
      expect(subject.match?(%w[Top Science])).to be_truthy
      expect(subject.match?(ltree['Top'])).to be_truthy
      expect(subject.match?('Other')).to be_falsey
      expect(subject.match?(nil)).to be_falsey
    end

    it 'works like a regular expression on the match operator' do
      subject = lquery['Top', :any]
      expect(subject =~ 'Top.Science').to be_eql(0)
      expect(subject =~ 'Other').to be_nil
      expect('Top.Science' =~ subject).to be_eql(0)
    end

    it 'matches a record by its primary key' do
      expect(lquery[root, :any].match?([root, 'Science'])).to be_truthy
      expect(lquery[root, :any].match?(root)).to be_truthy
      expect(lquery['Top', :any].match?(root)).to be_falsey
    end

    it 'sanitizes the path like a condition would' do
      Torque::PostgreSQL.config.ltree.sanitize = { '-' => '_' }
      expect(lquery.new('top.my-slug').match?('top.my_slug')).to be_truthy
      expect(lquery.new('top.my_slug').match?('top.my-slug')).to be_truthy
    end

    samples = [
      ['a.b.c.d.e',  'a.b.c.d.e',           true],
      ['a.b.c.d.e',  'A.b.c.d.e',           false],
      ['a.b.c.d.e',  'A@.b.c.d.e',          true],
      ['aa.b.c.d.e', 'A@.b.c.d.e',          false],
      ['aa.b.c.d.e', 'A*.b.c.d.e',          false],
      ['aa.b.c.d.e', 'A*@.b.c.d.e',         true],
      ['aa.b.c.d.e', 'A*@|g.b.c.d.e',       true],
      ['g.b.c.d.e',  'A*@|g.b.c.d.e',       true],
      ['a.b.c.d.e',  'a.*.e',               true],
      ['a.b.c.d.e',  'a.*{3}.e',            true],
      ['a.b.c.d.e',  'a.*{2}.e',            false],
      ['a.b.c.d.e',  'a.*{4}.e',            false],
      ['a.b.c.d.e',  'a.*{,4}.e',           true],
      ['a.b.c.d.e',  'a.*{2,}.e',           true],
      ['a.b.c.d.e',  'a.*{2,4}.e',          true],
      ['a.b.c.d.e',  'a.*{2,3}.e',          true],
      ['a.b.c.d.e',  'a.*{2,3}',            false],
      ['a.b.c.d.e',  'a.*{2,4}',            true],
      ['a.b.c.d.e',  'a.*{2,5}',            true],
      ['a.b.c.d.e',  '*{2,3}.e',            false],
      ['a.b.c.d.e',  '*{2,4}.e',            true],
      ['a.b.c.d.e',  '*{2,5}.e',            true],
      ['a.b.c.d.e',  '*.e',                 true],
      ['a.b.c.d.e',  '*.e.*',               true],
      ['a.b.c.d.e',  '*.d.*',               true],
      ['a.b.c.d.e',  '*.a.*.d.*',           true],
      ['a.b.c.d.e',  '*.!d.*',              true],
      ['a.b.c.d.e',  '*.!d',                true],
      ['a.b.c.d.e',  '!d.*',                true],
      ['a.b.c.d.e',  '!a.*',                false],
      ['a.b.c.d.e',  '*.!e',                false],
      ['a.b.c.d.e',  '*.!e.*',              true],
      ['a.b.c.d.e',  'a.*.!e',              false],
      ['a.b.c.d.e',  'a.*.!d',              true],
      ['a.b.c.d.e',  'a.*.!d.*',            true],
      ['a.b.c.d.e',  'a.*.!f.*',            true],
      ['a.b.c.d.e',  '*.a.*.!f.*',          true],
      ['a.b.c.d.e',  '*.a.*.!d.*',          true],
      ['a.b.c.d.e',  '*.a.!d.*',            true],
      ['a.b.c.d.e',  '*.a.!d',              false],
      ['a.b.c.d.e',  'a.!d.*',              true],
      ['a.b.c.d.e',  '*.!b.*',              true],
      ['a.b.c.d.e',  '*.!b.c.*',            false],
      ['a.b.c.d.e',  '*.!b.*.c.*',          true],
      ['a.b.c.d.e',  '!b.*.c.*',            true],
      ['a.b.c.d.e',  '!b.b.*',              true],
      ['a.b.c.d.e',  '!b.*.e',              true],
      ['a.b.c.d.e',  '!b.!c.*.e',           true],
      ['a.b.c.d.e',  '!b.*.!c.*.e',         true],
      ['a.b.c.d.e',  '*{2}.!b.*.!c.*.e',    true],
      ['a.b.c.d.e',  '*{1}.!b.*.!c.*.e',    false],
      ['a.b.c.d.e',  '*{1}.!b.*{1}.!c.*.e', false],
      ['a.b.c.d.e',  'a.!b.*{1}.!c.*.e',    false],
      ['a.b.c.d.e',  '!b.*{1}.!c.*.e',      false],
      ['a.b.c.d.e',  '*.!b.*{1}.!c.*.e',    false],
      ['a.b.c.d.e',  '*.!b.*.!c.*.e',       true],
      ['a.b.c.d.e',  '!b.!c.*',             true],
      ['a.b.c.d.e',  '!b.*.!c.*',           true],
      ['a.b.c.d.e',  '*{2}.!b.*.!c.*',      true],
      ['a.b.c.d.e',  '*{1}.!b.*.!c.*',      false],
      ['a.b.c.d.e',  '*{1}.!b.*{1}.!c.*',   false],
      ['a.b.c.d.e',  'a.!b.*{1}.!c.*',      false],
      ['a.b.c.d.e',  '!b.*{1}.!c.*',        false],
      ['a.b.c.d.e',  '*.!b.*{1}.!c.*',      true],
      ['a.b.c.d.e',  '*.!b.*.!c.*',         true],
      ['a.b.c.d.e',  'a.*{2}.*{2}',         true],
      ['a.b.c.d.e',  'a.*{1}.*{2}.e',       true],
      ['a.b.c.d.e',  'a.*{1}.*{4}',         false],
      ['a.b.c.d.e',  'a.*{5}.*',            false],
      ['5.0.1.0',    '5.!0.!0.0',           false],
      ['a.b',        '!a.!a',               false],
      ['a.b.c.d.e',  'a{,}',                false],
      ['a.b.c.d.e',  'a{1,}.*',             true],
      ['a.b.c.d.e',  'a{,}.!a{,}',          true],
      ['a.b.c.d.a',  'a{,}.!a{,}',          false],
      ['a.b.c.d.a',  'a{,2}.!a{1,}',        false],
      ['a.b.c.d.e',  'a{,2}.!a{1,}',        true],
      ['a.b.c.d.e',  '!x{,}',               true],
      ['a.b.c.d.e',  '!c{,}',               false],
      ['a.b.c.d.e',  '!c{0,3}.!a{2,}',      true],
      ['a.b.c.d.e',  '!c{0,3}.!d{2,}.*',    true],
      ['QWER_TY',    'q%@*',                true],
      ['QWER_TY',    'q%@*%@*',             true],
      ['QWER_TY',    'Q_t%@*',              true],
      ['QWER_GY',    'q_t%@*',              false],
    ]

    samples.each do |path, query, expected|
      it "agrees with PostgreSQL that '#{path}' ~ '#{query}' is #{expected}" do
        expect(lquery.new(query).match?(path)).to be(expected)
      end
    end

    it 'holds the same outcomes as the database for every sample' do
      rows = samples.map { |path, query, _| "('#{path}', '#{query}')" }
      result = connection.select_values(<<~SQL)
        SELECT path::ltree ~ query::lquery
        FROM (VALUES #{rows.join(', ')}) AS samples(path, query)
      SQL

      expect(result).to be_eql(samples.map(&:last))
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

    it 'contributes every item of a pattern' do
      expect(lquery[path_like.new('app.users'), :any].to_s).to be_eql('app.users.*')
      expect(lquery[path_like.new(['app', :any])].items).to be_eql(['app', :any])
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
      expect(ltree.new(path_like.new('app.users'))).not_to be_eql(%w[app users])
    end
  end

  context 'on markers' do
    it 'treats a plain path as a path' do
      expect(lquery.new('Top.Science')).not_to be_pattern
      expect(lquery.new(%w[Top Science])).not_to be_pattern
      expect(lquery.new(%i[Top Science])).not_to be_pattern
    end

    it 'treats anything with a query feature as a pattern' do
      expect(lquery.new(['Top', :any])).to be_pattern
      expect(lquery.new(['Top', 1..])).to be_pattern
      expect(lquery.new(['Top', %w[a b]])).to be_pattern
      expect(lquery.new('Top.*')).to be_pattern
      expect(lquery.new('!Top')).to be_pattern
      expect(lquery.new('Top@')).to be_pattern
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

    it 'does not apply to values read from the database' do
      Torque::PostgreSQL.config.ltree.sanitize = { 'a' => 'z' }
      expect(ltree_type.deserialize('a.b').to_s).to be_eql('a.b')
      expect(lquery_type.deserialize('a.*').to_s).to be_eql('a.*')
    end
  end

  context 'on OID' do
    it 'has the right types' do
      expect(ltree_type.type).to be_eql(:ltree)
      expect(lquery_type.type).to be_eql(:lquery)
    end

    it 'deserializes into a path' do
      expect(ltree_type.deserialize('Top.Science')).to be_a(ltree)
      expect(ltree_type.deserialize('Top.Science')).to be_eql(%w[Top Science])
      expect(ltree_type.deserialize(nil)).to be_nil
    end

    it 'serializes a path back into text' do
      expect(ltree_type.serialize(%w[Top Science])).to be_eql('Top.Science')
      expect(ltree_type.serialize('Top.Science')).to be_eql('Top.Science')
      expect(ltree_type.serialize(nil)).to be_nil
      expect(ltree_type.serialize('')).to be_nil
    end

    it 'deserializes a pattern into its items' do
      expect(lquery_type.deserialize('users.*')).to be_a(lquery)
      expect(lquery_type.deserialize('users.*')).to be_eql(['users', :any])
      expect(lquery_type.deserialize('a.*{2}')).to be_eql(['a', 2..2])
      expect(lquery_type.deserialize('a.*{1,}')).to be_eql(['a', 1..])
      expect(lquery_type.deserialize('a.*{,3}')).to be_eql(['a', ..3])
      expect(lquery_type.deserialize('a.*{0,2}')).to be_eql(['a', 0..2])
      expect(lquery_type.deserialize('a|b.c')).to be_eql([%w[a b], 'c'])
      expect(lquery_type.deserialize(nil)).to be_nil
    end

    it 'keeps negated and quantified groups as text' do
      expect(lquery_type.deserialize('!a|b.c{1,}')).to be_eql(['!a|b', 'c{1,}'])
    end

    it 'round trips the example from the PostgreSQL manual' do
      text = 'Top.*{0,2}.sport*@.!football|tennis{1,}.Russ*|Spain'
      items = ['Top', 0..2, 'sport*@', '!football|tennis{1,}', %w[Russ* Spain]]

      expect(lquery_type.deserialize(text)).to be_eql(items)
      expect(lquery_type.serialize(lquery_type.deserialize(text))).to be_eql(text)
    end

    it 'serializes a pattern back into text' do
      expect(lquery_type.serialize(['Top', :any])).to be_eql('Top.*')
      expect(lquery_type.serialize(lquery['Top', 1..])).to be_eql('Top.*{1,}')
      expect(lquery_type.serialize(nil)).to be_nil
    end
  end

  context 'on the model' do
    subject { Category.new }

    it 'reads and writes a path' do
      subject.path = 'Top.Science'
      expect(subject.path).to be_a(ltree)
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

    it 'round trips an array of paths' do
      user = User.create!(name: 'Rick', permissions: ['app.users.write', %w[app posts]])
      reloaded = User.find(user.id)

      expect(reloaded.permissions).to be_eql([%w[app users write], %w[app posts]])
      expect(reloaded.permissions.first).to be_a(ltree)
    end

    it 'reads and writes a pattern' do
      subject.pattern = ['users', :any]
      expect(subject.pattern).to be_a(lquery)
      expect(subject.pattern.items).to be_eql(['users', :any])
    end

    it 'round trips a pattern as its items' do
      subject.update!(title: 'Rule', pattern: ['users', :any, 1..2])
      expect(Category.find(subject.id).pattern.items).to be_eql(['users', :any, 1..2])
    end

    it 'round trips an array of patterns' do
      subject.update!(title: 'Rule', patterns: [['users', :any], 'posts.*{1,}'])
      reloaded = Category.find(subject.id)

      expect(reloaded.patterns).to be_eql([['users', :any], ['posts', 1..]])
      expect(reloaded.patterns.first).to be_a(lquery)
    end

    it 'tracks changes by the compiled form' do
      subject.update!(title: 'Rule', path: 'Top.Science', pattern: ['Top', :any])
      subject.path = %w[Top Science]
      subject.pattern = 'Top.*'
      expect(subject).not_to be_changed

      subject.pattern = ['Top', 1..]
      expect(subject).to be_changed
    end

    it 'leaves the validation to the database' do
      subject.path = 'Top.*'
      expect(subject.path).to be_eql(['Top', '*'])
      expect { subject.save! }.to raise_error(ActiveRecord::StatementInvalid)
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

    it 'takes a plain array as one path' do
      expect(subject.where(path: %w[Top Science]).to_sql).not_to include('IN')
    end

    it 'lists paths when the first entry is a whole one' do
      expect(subject.where(path: [%w[Top a], %w[Top b]]).to_sql)
        .to include(%[WHERE "categories"."path" IN ('Top.a', 'Top.b')])
      expect(subject.where(path: [ltree['Top'], 'Other']).to_sql)
        .to include(%[WHERE "categories"."path" IN ('Top', 'Other')])
    end

    it 'tests a list of patterns at once' do
      expect(subject.where(path: [['Top', :any], lquery['Other', 1..]]).to_sql)
        .to include(%[WHERE "categories"."path" ? '{Top.*,"Other.*{1,}"}'::lquery[]])
    end

    it 'handles nil and an empty list' do
      expect(subject.where(path: nil).to_sql).to include(%[WHERE "categories"."path" IS NULL])
      expect(subject.where(path: []).to_sql).to include('WHERE 1=0')
    end

    it 'finds the records that match' do
      Category.create!(title: 'Science', path: 'Top.Science')
      Category.create!(title: 'Astronomy', path: 'Top.Science.Astronomy')
      Category.create!(title: 'Hobbies', path: 'Top.Hobbies')

      expect(Category.where(path: ['Top', :any]).count).to be_eql(3)
      expect(Category.where(path: %w[Top Science]).count).to be_eql(1)
      expect(Category.where(path: ['Top', 'Science', :any]).count).to be_eql(2)
      expect(Category.where(path: [%w[Top Science], %w[Top Hobbies]]).count).to be_eql(2)
      expect(Category.where(path: [['Top', 'Sci*'], ['Nope', :any]]).count).to be_eql(1)
    end

    context 'on an array of paths' do
      subject { User.all }

      it 'asks whether any entry is the path' do
        expect(subject.where(permissions: 'app.users').to_sql)
          .to include(%[WHERE 'app.users' = ANY("users"."permissions")])
      end

      it 'matches the entries against a pattern' do
        expect(subject.where(permissions: ['app', :any]).to_sql)
          .to include(%[WHERE "users"."permissions" ~ 'app.*'::lquery])
      end

      it 'overlaps with a list of paths' do
        expect(subject.where(permissions: [%w[app users], %w[app posts]]).to_sql)
          .to include(%[WHERE "users"."permissions" && '{app.users,app.posts}'])
      end

      it 'tests the entries against a list of patterns' do
        expect(subject.where(permissions: [['app', :any], ['other', :any]]).to_sql)
          .to include(%[WHERE "users"."permissions" ? '{app.*,other.*}'::lquery[]])
      end

      it 'handles nil and an empty list' do
        expect(subject.where(permissions: nil).to_sql)
          .to include(%[WHERE "users"."permissions" IS NULL])
        expect(subject.where(permissions: []).to_sql)
          .to include(%[WHERE CARDINALITY("users"."permissions") = 0])
      end

      it 'finds the records that match' do
        User.create!(name: 'Editor', permissions: ['app.posts', 'app.users'])
        User.create!(name: 'Guest', permissions: ['app.posts'])

        expect(User.where(permissions: 'app.users').pluck(:name)).to be_eql(%w[Editor])
        expect(User.where(permissions: ['app', 'u*']).pluck(:name)).to be_eql(%w[Editor])
        expect(User.where(permissions: [%w[app users], %w[nope]]).pluck(:name)).to be_eql(%w[Editor])
        expect(User.where(permissions: [['app', :any]]).count).to be_eql(2)
      end
    end

    context 'on a pattern column' do
      it 'compares a pattern by its text' do
        expect(subject.where(pattern: ['users', :any]).to_sql)
          .to include(%[WHERE "categories"."pattern"::text = 'users.*'])
      end

      it 'matches a path against the stored pattern' do
        expect(subject.where(pattern: 'users.admin').to_sql)
          .to include(%[WHERE "categories"."pattern" ~ 'users.admin'::ltree])
      end

      it 'lists patterns by their text' do
        expect(subject.where(pattern: [['users', :any], ['posts', :any]]).to_sql)
          .to include(%[WHERE "categories"."pattern"::text IN ('users.*', 'posts.*')])
      end

      it 'matches any of the paths' do
        expect(subject.where(pattern: [%w[users admin], %w[posts new]]).to_sql)
          .to include(%[WHERE "categories"."pattern" ~ ANY('{users.admin,posts.new}'::ltree[])])
      end

      it 'finds the patterns that match' do
        Category.create!(title: 'Users', pattern: ['users', :any])
        Category.create!(title: 'Posts', pattern: ['posts', 1..])

        expect(Category.where(pattern: 'users.admin').pluck(:title)).to be_eql(%w[Users])
        expect(Category.where(pattern: ['users', :any]).pluck(:title)).to be_eql(%w[Users])
        expect(Category.where(pattern: [%w[users admin], %w[posts new]]).pluck(:title))
          .to match_array(%w[Users Posts])
      end
    end

    context 'on an array of patterns' do
      it 'asks whether any entry is the pattern' do
        expect(subject.where(patterns: ['users', :any]).to_sql)
          .to include(%[WHERE 'users.*' = ANY("categories"."patterns"::text[])])
      end

      it 'matches a path against any entry' do
        expect(subject.where(patterns: 'users.admin').to_sql)
          .to include(%[WHERE 'users.admin'::ltree ~ ANY("categories"."patterns")])
      end

      it 'overlaps with a list of patterns by their text' do
        expect(subject.where(patterns: [['users', :any], ['posts', :any]]).to_sql)
          .to include(%[WHERE "categories"."patterns"::text[] && '{users.*,posts.*}'])
      end

      it 'tests the entries against a list of paths' do
        expect(subject.where(patterns: [%w[users admin], %w[posts new]]).to_sql)
          .to include(%[WHERE "categories"."patterns" ? '{users.admin,posts.new}'::ltree[]])
      end

      it 'finds the records whose patterns match' do
        Category.create!(title: 'Rule', patterns: [['users', :any], ['posts', 1..]])

        expect(Category.where(patterns: 'users.admin').count).to be_eql(1)
        expect(Category.where(patterns: 'nope.x').count).to be_eql(0)
        expect(Category.where(patterns: ['users', :any]).count).to be_eql(1)
        expect(Category.where(patterns: [%w[posts new], %w[nope]]).count).to be_eql(1)
        expect(Category.where(patterns: [['users', :any], ['x', :any]]).count).to be_eql(1)
      end
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
      expect(User.where(permissions: ['app', 'users', :any]).pluck(:name)).to match_array(%w[Editor])
    end
  end
end
