require 'spec_helper'

RSpec.describe 'TableInheritance' do
  let(:connection) { ActiveRecord::Base.connection }

  context 'on migration' do
    mock_create_table

    it 'does not affect some basic forms of table creation' do
      sql = connection.create_table('schema_migrations', id: false) do |t|
        t.string :version, **connection.internal_string_options_for_primary_key
      end

      result = 'CREATE TABLE "schema_migrations"'
      result << ' \("version" character varying( NOT NULL)? PRIMARY KEY\)'
      expect(sql).to match(/#{result}/)
    end

    it 'does not affect simple table creation' do
      sql = connection.create_table(:activities) do |t|
        t.string :title
        t.boolean :active
        t.timestamps
      end

      result = 'CREATE TABLE "activities" ('
      result << '"id" bigserial primary key'
      result << ', "title" character varying'
      result << ', "active" boolean'
      result << ', "created_at" timestamp(6) NOT NULL'
      result << ', "updated_at" timestamp(6) NOT NULL'
      result << ')'
      expect(sql).to eql(result)
    end

    it 'does not affect temporary table creation based on a query' do
      query = 'SELECT * FROM "authors"'
      sql = connection.create_table(:test, temporary: true, as: query)

      result = 'CREATE TEMPORARY TABLE "test"'
      result << "  AS #{query}"
      expect(sql).to eql(result)
    end

    it 'adds the inherits statement for a single inheritance' do
      sql = connection.create_table(:activity_videos, inherits: :activities) do |t|
        t.string :url
      end

      result = 'CREATE TABLE "activity_videos" ('
      result << '"url" character varying'
      result << ') INHERITS ( "activities" )'
      expect(sql).to eql(result)
    end

    it 'adds the inherits statement for a multiple inheritance' do
      sql = connection.create_table(:activity_tests, inherits: [:activities, :tests]) do |t|
        t.string :grade
      end

      result = 'CREATE TABLE "activity_tests" ('
      result << '"grade" character varying'
      result << ') INHERITS ( "activities" , "tests" )'
      expect(sql).to eql(result)
    end

    it 'allows empty-body create table operation' do
      sql = connection.create_table(:activity_posts, inherits: :activities)
      result = "CREATE TABLE \"activity_posts\" ()"
      result << ' INHERITS ( "activities" )'
      expect(sql).to eql(result)
    end
  end

  context 'on schema' do
    let(:source) { ActiveRecord::Base.connection_pool }
    let(:dump_result) do
      ActiveRecord::SchemaDumper.dump(source, (dump_result = StringIO.new))
      dump_result.string
    end

    it 'dumps single inheritance with body' do
      parts = '"activity_books"'
      parts << ', id: false'
      parts << ', inherits: "activities"'
      parts << ', force: :cascade'
      expect(dump_result).to match(/create_table #{parts} do /)
    end

    it 'dumps single inheritance without body' do
      parts = '"activity_post_samples"'
      parts << ', id: false'
      parts << ', inherits: "activity_posts"'
      parts << ', force: :cascade'
      expect(dump_result).to match(/create_table #{parts}(?! do \|t\|)/)
    end

    it 'dumps multiple inheritance' do
      parts = '"activity_posts"'
      parts << ', id: false'
      parts << ', inherits: (\["images", "activities"\]|\["activities", "images"\])'
      parts << ', force: :cascade'
      expect(dump_result).to match(/create_table #{parts}/)
    end
  end

  context 'on syncing features' do
    let(:parent) { 'sync_parents' }
    let(:child) { 'sync_children' }
    let(:migration) { ActiveRecord::Migration::Current.new('Testing') }

    before do
      allow_any_instance_of(ActiveRecord::Migration).to receive(:puts)

      connection.create_table(:sync_targets) { |t| t.string :name }
      connection.create_table(parent) do |t|
        t.string :title
        t.string :code
        t.integer :author_id
        t.tsrange :during
      end

      connection.add_index parent, :title
      connection.add_unique_constraint parent, [:code]
      connection.add_exclusion_constraint parent, 'during WITH &&', using: :gist
      connection.add_foreign_key parent, :sync_targets, column: :author_id

      connection.create_table(child, inherits: parent) { |t| t.string :extra }
    end

    it 'copies the primary key, which postgresql does not inherit' do
      expect(connection.primary_keys(child)).to be_empty
      connection.sync_inheritance_features(parent)
      expect(connection.primary_keys(child)).to eql(%w[id])
    end

    it 'copies the indexes of the parent' do
      connection.sync_inheritance_features(parent)
      expect(connection.indexes(child).map(&:columns)).to include(%w[title])
    end

    it 'copies the unique constraints of the parent' do
      connection.sync_inheritance_features(parent)
      expect(connection.unique_constraints(child).map(&:column)).to eql([%w[code]])
    end

    it 'copies the exclusion constraints of the parent' do
      connection.sync_inheritance_features(parent)
      expect(connection.exclusion_constraints(child).map(&:expression)).to eql(['during WITH &&'])
    end

    it 'copies the outgoing foreign keys of the parent' do
      connection.sync_inheritance_features(parent)
      expect(connection.foreign_keys(child).map(&:to_table)).to eql(%w[sync_targets])
    end

    it 'excludes a feature that was asked for as false' do
      connection.sync_inheritance_features(parent, primary_key: false)

      expect(connection.primary_keys(child)).to be_empty
      expect(connection.indexes(child).map(&:columns)).to include(%w[title])
    end

    it 'takes any feature asked for as true as the whole selection' do
      connection.sync_inheritance_features(parent, indexes: true)

      expect(connection.indexes(child).map(&:columns)).to include(%w[title])
      expect(connection.primary_keys(child)).to be_empty
      expect(connection.unique_constraints(child)).to be_empty
      expect(connection.foreign_keys(child)).to be_empty
    end

    it 'refuses a feature it does not know about' do
      expect do
        connection.sync_inheritance_features(parent, comments: true)
      end.to raise_error(ArgumentError, /comments/)
    end

    it 'names every copy after the marker' do
      connection.sync_inheritance_features(parent)
      names = connection.indexes(child).map(&:name) + connection.foreign_keys(child).map(&:name)

      expect(names).to all(match(/\Async_inh_[0-9a-f]{10}\z/))
      expect(names.map(&:size)).to all(be(19))
    end

    it 'gives a copy the same name every single time' do
      connection.sync_inheritance_features(parent, indexes: true)
      names = connection.indexes(child).map(&:name).sort

      connection.indexes(child).each { |item| connection.remove_index(child, name: item.name) }
      connection.sync_inheritance_features(parent, indexes: true)

      expect(connection.indexes(child).map(&:name).sort).to eql(names)
    end

    it 'does not issue any statement on a second run' do
      connection.sync_inheritance_features(parent)

      statements = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        statements << payload[:sql] if payload[:sql].match?(/\A(CREATE|ALTER|DROP)/i)
      end

      connection.sync_inheritance_features(parent)
      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(statements).to be_empty
    end

    it 'leaves an equivalent index the child already has alone' do
      connection.add_index child, :title, name: 'written_by_hand'
      connection.sync_inheritance_features(parent)

      titles = connection.indexes(child).select { |item| item.columns == %w[title] }
      expect(titles.map(&:name)).to eql(%w[written_by_hand])
    end

    it 'copies the index that backs a constraint only through the constraint' do
      connection.sync_inheritance_features(parent)

      codes = connection.indexes(child).select { |item| item.columns == %w[code] }
      expect(codes.size).to be(1)
      expect(codes.first.name).to eql(connection.unique_constraints(child).first.name)
    end

    it 'cascades, carrying what each level added of its own' do
      connection.add_index child, :extra
      connection.create_table(:sync_grandchildren, inherits: child)

      connection.sync_inheritance_features(parent)

      columns = connection.indexes('sync_grandchildren').map(&:columns)
      expect(columns).to include(%w[title])
      expect(columns).to include(%w[extra])
    end

    it 'writes only to the children it was given' do
      connection.create_table(:sync_grandchildren, inherits: child)
      connection.sync_inheritance_features(parent, [child])

      expect(connection.indexes(child).map(&:columns)).to include(%w[title])
      expect(connection.indexes('sync_grandchildren')).to be_empty
    end

    it 'pulls only from the parents that are inside the requested tree' do
      connection.create_table(:sync_others, id: false) { |t| t.string :label }
      connection.add_index :sync_others, :label
      connection.create_table(:sync_mixed, inherits: [parent, :sync_others])

      connection.sync_inheritance_features(parent)

      columns = connection.indexes('sync_mixed').map(&:columns)
      expect(columns).to include(%w[title])
      expect(columns).not_to include(%w[label])
    end

    it 'refuses a table that does not inherit from the parent' do
      expect do
        connection.sync_inheritance_features(parent, %w[authors])
      end.to raise_error(ArgumentError, /authors/)
    end

    it 'drops a copy whose source is gone when pruning' do
      connection.sync_inheritance_features(parent)
      connection.remove_index(parent, :title)
      connection.sync_inheritance_features(parent, prune: true)

      expect(connection.indexes(child).map(&:columns)).not_to include(%w[title])
    end

    it 'keeps an index written by hand when pruning, even on an inherited column' do
      connection.add_index child, :title, name: 'written_by_hand'
      connection.remove_index(parent, :title)
      connection.sync_inheritance_features(parent, prune: true)

      expect(connection.indexes(child).map(&:name)).to include('written_by_hand')
    end

    it 'never drops the primary key when pruning' do
      connection.sync_inheritance_features(parent)
      connection.execute("ALTER TABLE #{parent} DROP CONSTRAINT #{parent}_pkey")
      connection.sync_inheritance_features(parent, prune: true)

      expect(connection.primary_keys(child)).to eql(%w[id])
    end

    it 'syncs everything when the table is created with sync' do
      connection.create_table(:sync_others, inherits: parent, sync: true) { |t| t.string :note }

      expect(connection.primary_keys('sync_others')).to eql(%w[id])
      expect(connection.indexes('sync_others').map(&:columns)).to include(%w[title])
      expect(connection.foreign_keys('sync_others').map(&:to_table)).to eql(%w[sync_targets])
    end

    it 'syncs from every parent named by a multiple inheritance' do
      connection.create_table(:sync_others, id: false) { |t| t.string :label }
      connection.add_index :sync_others, :label
      connection.create_table(:sync_mixed, inherits: [parent, :sync_others], sync: true)

      columns = connection.indexes('sync_mixed').map(&:columns)
      expect(columns).to include(%w[title])
      expect(columns).to include(%w[label])
    end

    it 'syncs only what the sync option picks' do
      connection.create_table(:sync_others, inherits: parent, sync: { indexes: true })

      expect(connection.indexes('sync_others').map(&:columns)).to include(%w[title])
      expect(connection.primary_keys('sync_others')).to be_empty
      expect(connection.foreign_keys('sync_others')).to be_empty
    end

    it 'reverts into a sync that prunes' do
      connection.sync_inheritance_features(parent)
      connection.remove_index(parent, :title)

      migration.revert { migration.connection.sync_inheritance_features(parent) }

      expect(connection.indexes(child).map(&:columns)).not_to include(%w[title])
    end

    it 'prunes only once the parent is back to what it was' do
      connection.sync_inheritance_features(parent)
      expect(connection.indexes(child).map(&:columns)).to include(%w[title])

      migration.revert do
        migration.connection.add_index parent, :title
        migration.connection.sync_inheritance_features(parent)
      end

      expect(connection.indexes(parent).map(&:columns)).not_to include(%w[title])
      expect(connection.indexes(child).map(&:columns)).not_to include(%w[title])
    end

    context 'on schema' do
      let(:dump_result) do
        ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, (io = StringIO.new))
        io.string
      end

      before { connection.sync_inheritance_features(parent) }

      it 'describes an inherited primary key through the sync option' do
        line = dump_result.lines.find { |item| item.include?("create_table \"#{child}\"") }

        expect(line).to include('id: false')
        expect(line).to include(%[inherits: "#{parent}"])
        expect(line).to match(/sync: \{:?primary_key(?:: | => |=>)true\}/)
      end

      it 'never describes the inherited column all over again' do
        line = dump_result.lines.find { |item| item.include?("create_table \"#{child}\"") }

        expect(line).to include('id: false')
        expect(line).not_to match(/id: :\w+/)
        expect(line).not_to match(/, primary_key: /)
      end

      it 'carries the marker of every copy, so pruning still works after a load' do
        expect(dump_result).to match(/t\.index \["title"\], name: "sync_inh_[0-9a-f]{10}"/)
      end
    end
  end

  context 'on schema cache' do
    let(:schema_cache) { ActiveRecord::Base.connection.schema_cache }
    let(:schema_cache_reflection) { schema_cache.instance_variable_get(:@schema_reflection) }
    let(:new_schema_cache) { schema_cache_reflection.send(:cache, schema_cache_source) }
    let(:schema_cache_source) { schema_cache.instance_variable_get(:@pool) }

    subject { new_schema_cache }

    it 'correctly defines the associations' do
      scenario = {
        'M' => %w(N),
        'N' => %w(C),
        'C' => %w(B),
        'B' => %w(A),
        'D' => %w(A),
        'F' => %w(E),
        'G' => %w(E H),
      }

      subject.instance_variable_set(:@inheritance_loaded, true)
      subject.instance_variable_set(:@inheritance_dependencies, scenario)
      subject.instance_variable_set(:@inheritance_associations, subject.send(:generate_associations))
      subject.instance_variable_set(:@data_sources_model_names, {})
      expect(subject.instance_variable_get(:@inheritance_associations)).to eql({
        'A' => %w(B D C N M),
        'B' => %w(C N M),
        'C' => %w(N M),
        'N' => %w(M),
        'E' => %w(F G),
        'H' => %w(G),
      })
    end

    context 'on looking up models' do
      let(:prepare_arguments) { [schema_cache_source] }
      let(:prepare_method) { :add_all }

      after(:all) do
        schema_cache = ActiveRecord::Base.connection.schema_cache
        schema_cache.instance_variable_set(:@data_sources, {})
        schema_cache.instance_variable_set(:@data_sources_model_names, {})
      end

      it 'respect irregular names' do
        allow(Torque::PostgreSQL.config).to receive(:irregular_models).and_return({
          'public.posts' => 'ActivityPost',
        })

        subject.send(prepare_method, *prepare_arguments)
        list = subject.instance_variable_get(:@data_sources_model_names)
        expect(list).to have_key('public.posts')
        expect(list['public.posts']).to eql(ActivityPost)
      end

      it 'does not load irregular where the data source is not defined' do
        allow(Torque::PostgreSQL.config).to receive(:irregular_models).and_return({
          'products' => 'Product',
        })

        subject.send(prepare_method, *prepare_arguments)
        list = subject.instance_variable_get(:@data_sources_model_names)
        expect(list).to_not have_key('products')
      end

      it 'works with eager loading' do
        allow(Torque::PostgreSQL.config).to receive(:eager_load).and_return(true)
        ActivityPost.reset_table_name

        list = subject.instance_variable_get(:@data_sources_model_names)
        expect(list).to have_key('activity_posts')
        expect(list['activity_posts']).to eql(ActivityPost)
      end

      {
        'activities' => 'Activity',
        'activity_posts' => 'ActivityPost',
        'activity_post_samples' => 'ActivityPost::Sample',
      }.each do |table_name, expected_model|
        it "translate the table name #{table_name} to #{expected_model} model" do
          expect(subject.lookup_model(table_name)).to eql(expected_model.constantize)
        end
      end
    end
  end

  context 'on inheritance' do
    let(:base) { Activity }
    let(:child) { ActivityPost }
    let(:child2) { ActivityBook }
    let(:other) { AuthorJournalist }

    before { ActiveRecord::Base.connection.schema_cache.clear! }

    it 'identifies mergeable attributes' do
      result_base = %w(id author_id title active kind created_at updated_at description url file post_id)
      expect(base.inheritance_mergeable_attributes.sort).to eql(result_base.sort)
    end

    it 'has a merged version of attributes' do
      result_base = %w(id author_id title active kind created_at updated_at description url activated file post_id)
      result_child = %w(id author_id title active kind created_at updated_at file post_id url activated)
      result_child2 = %w(id author_id title active kind created_at updated_at description url activated)
      result_other = %w(id name type specialty)

      expect(base.inheritance_merged_attributes).to eql(result_base)
      expect(child.inheritance_merged_attributes).to eql(result_child)
      expect(child2.inheritance_merged_attributes).to eql(result_child2)
      expect(other.inheritance_merged_attributes).to eql(result_other)
    end

    it 'identifies physical inheritance' do
      expect(base.physically_inherited?).to be_falsey
      expect(child.physically_inherited?).to be_truthy
      expect(child2.physically_inherited?).to be_truthy
      expect(other.physically_inherited?).to be_falsey
    end

    it 'returns a list of dependent tables' do
      expect(base.inheritance_dependents).to eql(%w(activity_books activity_posts activity_post_samples))
      expect(child.inheritance_dependents).to eql(%w(activity_post_samples))
      expect(child2.inheritance_dependents).to eql(%w())
      expect(other.inheritance_dependents).to eql(%w())
    end

    it 'can check dependency' do
      expect(base.physically_inheritances?).to be_truthy
      expect(child.physically_inheritances?).to be_truthy
      expect(child2.physically_inheritances?).to be_falsey
      expect(other.physically_inheritances?).to be_falsey
    end

    it 'returns the list of models that the records can be casted to' do
      expect(base.casted_dependents.values.map(&:name)).to eql(%w(ActivityBook ActivityPost ActivityPost::Sample))
      expect(child.casted_dependents.values.map(&:name)).to eql(%w(ActivityPost::Sample))
      expect(child2.casted_dependents.values.map(&:name)).to eql(%w())
      expect(other.casted_dependents.values.map(&:name)).to eql(%w())
    end

    it 'only considers dependents that add columns as expandable' do
      expect(base.inheritance_expandable_dependents.keys).to \
        eql(%w(activity_books activity_posts activity_post_samples))
      expect(child.inheritance_expandable_dependents).to be_empty
      expect(child2.inheritance_expandable_dependents).to be_empty
    end

    it 'recomputes inheritance metadata after resetting column information' do
      base.casted_dependents
      base.inheritance_expandable_dependents
      base.physically_inheritances?
      base.inheritance_column_prefix
      base.inheritance_dependent_prefixes
      child2.inheritance_foreign_attribute_names
      base.reset_column_information

      expect(base.instance_variable_get(:@casted_dependents)).to be_nil
      expect(base.instance_variable_get(:@inheritance_expandable_dependents)).to be_nil
      expect(base.instance_variable_get(:@physically_inheritances)).to be_nil
      expect(base.instance_variable_get(:@inheritance_column_prefix)).to be_nil
      expect(base.instance_variable_get(:@inheritance_dependent_prefixes)).to be_nil
      expect(child2.instance_variable_get(:@inheritance_foreign_attribute_names)).to be_nil
      expect(base.casted_dependents.values.map(&:name)).to \
        eql(%w(ActivityBook ActivityPost ActivityPost::Sample))
    end

    it 'correctly generates the tables name' do
      expect(base.table_name).to eql('activities')
      expect(child.table_name).to eql('activity_posts')
      expect(child2.table_name).to eql('activity_books')
      expect(other.table_name).to eql('authors')
    end

    it 'respects the table name prefix and suffix defined on parent module' do
      mod = Object.const_set('Private', Module.new)
      mod.define_singleton_method(:table_name_prefix) { 'private.' }
      mod.define_singleton_method(:table_name_suffix) { '_bundle' }
      result = 'private.activity_post_others_bundle'

      klass = mod.const_set('Other', Class.new(ActivityPost))
      allow(klass).to receive(:module_parent).and_return(child)
      allow(klass).to receive(:module_parents).and_return([mod])
      allow(klass).to receive(:physically_inherited?).and_return(true)
      expect(klass.send(:compute_table_name)).to be_eql(result)
    end
  end

  context 'on partial records' do
    let(:record) { Activity.create!(title: 'Activity test') }

    it 'is neither partial nor read-only by default' do
      expect(record.partial_record?).to be_falsey
      expect(record.readonly?).to be_falsey
    end

    it 'becomes read-only when marked as partial' do
      record.send(:mark_as_partial_record!)

      expect(record.partial_record?).to be_truthy
      expect(record.readonly?).to be_truthy
      expect { record.update!(title: 'Changed') }.to \
        raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it 'clears both flags when marked as full' do
      record.send(:mark_as_partial_record!)
      record.send(:mark_as_full_record!)

      expect(record.partial_record?).to be_falsey
      expect(record.readonly?).to be_falsey
    end

    it 'clears the partial state on reload' do
      record.send(:mark_as_partial_record!)
      record.reload

      expect(record.partial_record?).to be_falsey
      expect(record.readonly?).to be_falsey
    end

    it 'keeps an explicit readonly through a reload on a non-inheriting model' do
      User.create!(name: 'A user')
      user = User.readonly.first

      expect(user.readonly?).to be_truthy
      expect(user.reload.readonly?).to be_truthy
    end

    it 'keeps an explicit readonly through a reload on a non-partial record' do
      record.readonly!
      expect(record.reload.readonly?).to be_truthy
    end
  end

  context 'on automatic casting' do
    before :each do
      Activity.create!(title: 'Plain activity')
      ActivityBook.create!(title: 'A book', url: 'bookurl1')
      ActivityPost.create!(title: 'A post', url: 'posturl1')
      ActivityPost::Sample.create!(title: 'A sample')
    end

    it 'returns the correct class without any opt-in' do
      expect(Activity.order(:id).load.map(&:class)).to \
        eql([Activity, ActivityBook, ActivityPost, ActivityPost::Sample])
    end

    it 'marks casted records as partial and read-only' do
      records = Activity.order(:id).load.to_a

      expect(records[0].partial_record?).to be_falsey
      expect(records[0].readonly?).to be_falsey
      expect(records[1].partial_record?).to be_truthy
      expect(records[1].readonly?).to be_truthy
    end

    it 'raises when reading a column that was not loaded' do
      book = Activity.order(:id).load.to_a[1]
      expect { book.url }.to raise_error(ActiveModel::MissingAttributeError)
    end

    it 'raises when persisting a partial record' do
      book = Activity.order(:id).load.to_a[1]
      expect { book.update!(title: 'Changed') }.to \
        raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it 'destroys a partial record from both tables' do
      book = Activity.order(:id).load.to_a[1]

      expect(book.readonly?).to be_truthy
      expect(book.destroy).to be_truthy
      expect(Activity.where(id: book.id)).to be_empty
      expect(ActivityBook.where(id: book.id)).to be_empty
    end

    it 'keeps a partial record read-only after destroying it' do
      book = Activity.order(:id).load.to_a[1]
      book.destroy

      expect(book.readonly?).to be_truthy
    end

    it 'destroys partial records through a dependent association' do
      author = Author.create!(name: 'An author name')
      book = ActivityBook.create!(title: 'Owned book', url: 'ownedurl', author: author)
      author.destroy

      expect(Activity.where(id: book.id)).to be_empty
      expect(ActivityBook.where(id: book.id)).to be_empty
    end

    it 'does not mark a dependent that adds no columns as partial' do
      sample = ActivityPost.order(:id).load.to_a.last

      expect(sample).to be_instance_of(ActivityPost::Sample)
      expect(sample.partial_record?).to be_falsey
      expect(sample.readonly?).to be_falsey
      expect(sample.update!(title: 'Changed')).to be_truthy
    end

    it 'loads the full record on reload' do
      book = Activity.order(:id).load.to_a[1]
      book.reload

      expect(book.url).to eql('bookurl1')
      expect(book.partial_record?).to be_falsey
      expect(book.readonly?).to be_falsey
      expect(book.changed?).to be_falsey
    end

    it 'does not expose the internal record class attribute' do
      book = Activity.order(:id).load.to_a[1]

      expect(book).to be_instance_of(ActivityBook)
      expect(book).not_to respond_to(:_record_class)
    end

    it 'does not expose the internal record class attribute on a non-casted record' do
      plain = Activity.order(:id).load.first

      expect(plain).to be_instance_of(Activity)
      expect(plain).not_to respond_to(:_record_class)
      expect(plain.attributes).not_to have_key('_record_class')
      expect { Activity.new(plain.attributes) }.not_to raise_error
    end

    it 'does not affect single table inheritance' do
      AuthorJournalist.create!(name: 'An author name')
      expect(AuthorJournalist.first).to be_instance_of(AuthorJournalist)
    end

    it 'does not cast records loaded through an explicit select' do
      book = ActivityBook.create!(title: 'Selected book', url: 'selurl')
      record = nil

      expect { record = Activity.select(:id, :title).where(id: book.id).first }.to \
        output(/Activity .* omits :_regclass/).to_stderr

      expect(record).to be_instance_of(Activity)
      expect(record.partial_record?).to be_falsey
      expect(record.readonly?).to be_falsey
    end

    it 'casts records when the select asks for the record class column' do
      book = ActivityBook.create!(title: 'Selected book', url: 'selurl')
      record = Activity.select(:_regclass, :id, :title).where(id: book.id).first

      expect(record).to be_instance_of(ActivityBook)
      expect(record.partial_record?).to be_truthy
      expect(record.readonly?).to be_truthy
    end

    it 'keeps extra selected columns on both casted and non-casted records' do
      author = Author.create!(name: 'The author')
      Activity.create!(title: 'Joined activity', author: author)
      ActivityBook.create!(title: 'Joined book', url: 'jburl', author: author)

      records = Activity.joins(:author).where(author_id: author.id)
        .select(:_regclass, 'activities.*', 'authors.name as author_name')
        .order(:id).to_a

      expect(records[0]).to be_instance_of(Activity)
      expect(records[1]).to be_instance_of(ActivityBook)
      expect(records[0][:author_name]).to eql('The author')
      expect(records[1][:author_name]).to eql('The author')
    end

    it 'keeps a user alias containing a double underscore on both plain and casted records' do
      author = Author.create!(name: 'Underscore author')
      Activity.create!(title: 'Underscore activity', author: author)
      ActivityBook.create!(title: 'Underscore book', url: 'underscoreurl', author: author)

      records = Activity.joins(:author).where(author_id: author.id)
        .select(:_regclass, 'activities.*', 'authors.name as custom__alias')
        .order(:id).to_a

      expect(records[0]).to be_instance_of(Activity)
      expect(records[1]).to be_instance_of(ActivityBook)
      expect(records[0][:custom__alias]).to eql('Underscore author')
      expect(records[1][:custom__alias]).to eql('Underscore author')
    end

    it 'warns when an explicit select fails to cast the loaded records' do
      expect { Activity.select(:id, :title).to_a }.to \
        output(/Activity .* omits :_regclass/).to_stderr
    end

    it 'does not warn when the record class column ends up selected' do
      expect { Activity.select(:_regclass, :id).to_a }.not_to output.to_stderr
      expect { Activity.select(:_regclass, :id).select(:title).to_a }.not_to output.to_stderr
      expect { Activity.select(:id).select(:_regclass).to_a }.not_to output.to_stderr
      expect { Activity.itself_only.select(:id).to_a }.not_to output.to_stderr
      expect { AuthorJournalist.select(:id).to_a }.not_to output.to_stderr
    end

    it 'does not warn when a marker-bearing select returns only parent-table rows' do
      plain = Activity.order(:id).first

      expect { Activity.select(:_regclass, :id, :title).where(id: plain.id).to_a }.not_to \
        output.to_stderr
    end

    it 'does not warn when the record class column is hand-written as raw SQL' do
      plain = Activity.order(:id).first

      expect {
        Activity.select('tableoid::regclass AS _record_class', :id, :title).where(id: plain.id).to_a
      }.not_to output.to_stderr
    end

    it 'does not warn about a relation only used to build a subquery' do
      ActivityBook.create!(title: 'Sub author book', url: 'subauthorurl')

      expect { Author.where(id: Activity.all) }.not_to output.to_stderr
    end

    it 'warns only once when an association scope is built more than once' do
      Author.has_many :selected_activities, -> { select(:id, :title) },
        class_name: 'Activity', foreign_key: :author_id

      author = Author.create!(name: 'Repeated author')
      ActivityBook.create!(title: 'Repeated book', url: 'repeaturl', author: author)

      expect { author.selected_activities.to_a }.to \
        output(/\A[^\n]*omits :_regclass[^\n]*\n\z/).to_stderr
    end

    it 'does not warn while building an auxiliary statement over an inheriting model' do
      expect { Activity.select(:id, :title).arel }.not_to output.to_stderr
    end

    it 'translates the record class token into the marker' do
      sql = Activity.select(:_regclass, :id).to_sql

      expect(sql).to include('"activities"."tableoid"::regclass AS _record_class')
      expect(sql).not_to include('"_regclass"')
    end

    it 'adds the record class exactly once through repeated chaining' do
      relation = Activity.all
      3.times do
        relation = relation.where(active: nil)
        relation.to_a
      end

      expect(relation.to_sql.scan('_record_class').size).to eql(1)
    end

    it 'does not add the record class to a relation used as a subquery' do
      author = Author.create!(name: 'Sub author')
      ActivityBook.create!(title: 'Sub book', url: 'suburl', author: author)

      expect(Author.where(id: Activity.select(:author_id)).to_a).to eql([author])
    end

    it 'does not add the record class to a grouped selection' do
      expect(Activity.select(:kind).group(:kind).to_a.size).to eql(1)
      expect(Activity.group(:kind).exists?).to be_truthy
    end

    it 'does not add the record class to a distinct selection' do
      ActivityBook.create!(title: 'Plain activity', url: 'duperurl')

      expect(Activity.distinct.select(:title).map(&:title)).to \
        match_array(['Plain activity', 'A book', 'A post', 'A sample'])
    end

    it 'does not add the record class when reading from a subquery' do
      records = Activity.from(Activity.itself_only, :activities).to_a

      expect(records.size).to eql(1)
      expect(records.first.title).to eql('Plain activity')
    end

    it 'does not add the record class to plucked columns' do
      ActivityBook.create!(title: 'Plucked', url: 'plurl')
      expect(Activity.pluck(:title)).to all(be_a(String))
      expect(Activity.pluck(:id, :title).first.size).to eql(2)
    end

    it 'does not add the record class to calculations' do
      ActivityBook.create!(title: 'Counted', url: 'cnturl')
      expect(Activity.count).to be_a(Integer)
      expect(Activity.sum(:id)).to be_a(Integer)
    end

    it 'does not break calculations combined with buckets' do
      ActivityBook.create!(title: 'Bucketed', url: 'bkturl')
      expect { Activity.buckets(:id, 0..50, count: 5).count }.not_to raise_error
      expect { User.buckets(:age, 0..50, count: 5).count }.not_to raise_error
    end

    it 'still casts a relation that was previously used for a calculation' do
      book = ActivityBook.create!(title: 'Reused', url: 'reurl')
      relation = Activity.where(id: book.id)
      relation.count

      expect(relation.to_a.first).to be_instance_of(ActivityBook)
    end

    it 'does not add the record class when plucking an explicit selection' do
      ActivityBook.create!(title: 'Selected pluck', url: 'spurl')
      expect(Activity.select(:id, :title).pluck(:id).first).to be_a(Integer)
    end

    context 'when a record class cannot be resolved' do
      after { Activity.reset_column_information }

      it 'raises pointing at the irregular models setting' do
        Activity.instance_variable_set(:@casted_dependents, {})

        expect { Activity.order(:id).load.to_a }.to \
          raise_error(Torque::PostgreSQL::InheritanceError, /activity_books/)
      end
    end

    context 'using uuid' do
      it 'returns the correct class' do
        Question.create!(title: 'Simple question')
        QuestionSelect.create!(title: 'Select question')

        expect(Question.order(:created_at).load.map(&:class)).to \
          eql([Question, QuestionSelect])
      end
    end
  end

  context 'on relation' do
    let(:base) { Activity }
    let(:child) { ActivityBook }
    let(:other) { AuthorJournalist }

    it 'has operation methods' do
      expect(base).to respond_to(:itself_only)
      expect(base).to respond_to(:expand_records)
    end

    context 'itself only' do
      it 'adds the record class to queries on a table with dependents' do
        result = 'SELECT "activities".*'
        result << ', "activities"."tableoid"::regclass AS _record_class'
        result << ' FROM "activities"'
        expect(base.all.to_sql).to eql(result)
      end

      it 'does not add the record class to a table without dependents' do
        expect(other.all.to_sql).to \
          eql("SELECT \"authors\".* FROM \"authors\" WHERE \"authors\".\"type\" = 'AuthorJournalist'")
      end

      it 'adds the only condition to the query' do
        expect(base.itself_only.to_sql).to \
          eql('SELECT "activities".* FROM ONLY "activities"')
      end

      it 'returns the right ammount of entries' do
        base.create!(title: 'Activity only')
        child.create!(title: 'Activity book')

        expect(base.count).to eql(2)
        expect(base.itself_only.count).to eql(1)
        expect(child.count).to eql(1)
      end
    end

    context 'expand records' do
      before :each do
        base.create(title: 'Activity test')
        child.create(title: 'Activity book', url: 'bookurl1')
        other.create(name: 'An author name')
      end

      it 'does not mess with single table inheritance' do
        result = 'SELECT "authors".* FROM "authors"'
        result << " WHERE \"authors\".\"type\" = 'AuthorJournalist'"
        expect(other.all.to_sql).to eql(result)
      end

      it 'adds all statements to load all the necessary records' do
        result = 'SELECT "activities".*, "activities"."tableoid"::regclass AS _record_class, "i_0"."description"'
        result << ', COALESCE("i_0"."url", "i_1"."url", "i_2"."url") AS url, "i_0"."activated" AS activity_books__activated'
        result << ', "i_1"."activated" AS activity_posts__activated, "i_2"."activated" AS activity_post_samples__activated'
        result << ', COALESCE("i_1"."file", "i_2"."file") AS file, COALESCE("i_1"."post_id", "i_2"."post_id") AS post_id'
        result << ' FROM "activities"'
        result << ' LEFT OUTER JOIN "activity_books" "i_0" ON "activities"."id" = "i_0"."id"'
        result << ' LEFT OUTER JOIN "activity_posts" "i_1" ON "activities"."id" = "i_1"."id"'
        result << ' LEFT OUTER JOIN "activity_post_samples" "i_2" ON "activities"."id" = "i_2"."id"'
        expect(base.expand_records(eager_load: true).all.to_sql).to eql(result)
      end

      it 'can be have simplefied joins' do
        result = 'SELECT "activities".*, "activities"."tableoid"::regclass AS _record_class'
        result << ', "i_0"."description", "i_0"."url", "i_0"."activated"'
        result << ' FROM "activities"'
        result << ' LEFT OUTER JOIN "activity_books" "i_0" ON "activities"."id" = "i_0"."id"'
        expect(base.expand_records(child, eager_load: true).all.to_sql).to eql(result)
      end

      it 'can be filtered by record type' do
        result = 'SELECT "activities".*, "activities"."tableoid"::regclass AS _record_class'
        result << ', "i_0"."description", "i_0"."url", "i_0"."activated"'
        result << ' FROM "activities"'
        result << ' LEFT OUTER JOIN "activity_books" "i_0" ON "activities"."id" = "i_0"."id"'
        result << " WHERE \"activities\".\"tableoid\"::regclass::varchar IN ('activity_books')"
        expect(base.expand_records(child, filter: true, eager_load: true).all.to_sql).to eql(result)
      end

      it 'works with count and does not add extra columns' do
        result = 'SELECT COUNT(*)'
        result << ' FROM "activities"'
        result << ' LEFT OUTER JOIN "activity_books" "i_0" ON "activities"."id" = "i_0"."id"'
        result << ' LEFT OUTER JOIN "activity_posts" "i_1" ON "activities"."id" = "i_1"."id"'
        result << ' LEFT OUTER JOIN "activity_post_samples" "i_2" ON "activities"."id" = "i_2"."id"'
        query = get_last_executed_query{ base.expand_records(eager_load: true).all.count }
        expect(query).to eql(result)
      end

      it 'works with sum and does not add extra columns' do
        result = 'SELECT SUM("activities"."id")'
        result << ' FROM "activities"'
        result << ' LEFT OUTER JOIN "activity_books" "i_0" ON "activities"."id" = "i_0"."id"'
        result << ' LEFT OUTER JOIN "activity_posts" "i_1" ON "activities"."id" = "i_1"."id"'
        result << ' LEFT OUTER JOIN "activity_post_samples" "i_2" ON "activities"."id" = "i_2"."id"'
        query = get_last_executed_query{ base.expand_records(eager_load: true).all.sum(:id) }
        expect(query).to eql(result)
      end

      it 'does not accumulate the extra columns through repeated chaining' do
        relation = base.expand_records(eager_load: true)
        3.times do
          relation = relation.where(active: nil)
          relation.to_a
        end

        sql = relation.to_sql
        expect(sql.scan('_record_class').size).to eql(1)
        expect(sql.scan('"i_0"."description"').size).to eql(1)
      end

      it 'filters by every expandable dependent when no type is given' do
        ActivityPost.create(title: 'Activity post', url: 'posturl1')
        records = base.expand_records(filter: true).order(:id).to_a

        expect(records.map(&:class)).to eql([ActivityBook, ActivityPost])
        expect(records.map(&:url)).to eql(['bookurl1', 'posturl1'])
      end

      it 'returns the correct model object' do
        ActivityPost.create(title: 'Activity post')
        ActivityPost::Sample.create(title: 'Activity post')
        records = base.expand_records(eager_load: true).order(:id).load.to_a

        expect(records[0]).to be_instance_of(Activity)
        expect(records[1]).to be_instance_of(ActivityBook)
        expect(records[2]).to be_instance_of(ActivityPost)
        expect(records[3]).to be_instance_of(ActivityPost::Sample)
      end

      it 'only fully loads the requested records' do
        ActivityPost.create(title: 'Activity post')
        records = base.expand_records(ActivityBook, eager_load: true).order(:id).load.to_a

        expect(records[1]).to be_instance_of(ActivityBook)
        expect(records[1].partial_record?).to be_falsey
        expect(records[2]).to be_instance_of(ActivityPost)
        expect(records[2].partial_record?).to be_truthy
      end

      it 'correctly identifies same name attributes' do
        ActivityPost.create(title: 'Activity post', url: 'posturl1')
        records = base.expand_records(eager_load: true).order(:id).load.to_a

        expect(records[1].url).to eql('bookurl1')
        expect(records[2].url).to eql('posturl1')
      end

      it 'does not make internal inheritance attributes accessible' do
        record = base.expand_records(eager_load: true).order(:id).load.last

        expect(record).to be_instance_of(ActivityBook)
        expect(record).not_to respond_to(:_record_class)
      end

      it 'drops sibling dependent columns from a casted record' do
        ActivityPost.create(title: 'Activity post', url: 'posturl1')
        record = base.expand_records(eager_load: true).order(:id).load[1]

        expect(record).to be_instance_of(ActivityBook)
        expect(record.url).to eql('bookurl1')
        expect(record.attributes).not_to have_key('file')
        expect(record.attributes).not_to have_key('post_id')
        expect { ActivityBook.new(record.attributes) }.not_to raise_error
      end

      it 'drops a genuine dependent-prefixed column from a casted record' do
        ActivityPost.create(title: 'Activity post', url: 'posturl1')
        record = base.expand_records(eager_load: true).order(:id).load[1]

        expect(record).to be_instance_of(ActivityBook)
        expect(record.attributes).not_to have_key('activity_posts__activated')
      end

      it 'drops sibling dependent columns from a non-casted parent record' do
        record = base.expand_records(eager_load: true).order(:id).load[0]

        expect(record).to be_instance_of(Activity)
        expect(record.attributes).not_to have_key('description')
        expect(record.attributes).not_to have_key('url')
        expect { Activity.new(record.attributes) }.not_to raise_error
      end

      it 'defaults to every dependent that adds columns' do
        relation = base.expand_records
        expect(relation.expand_records_values).to \
          eql(base.inheritance_expandable_dependents.values)
      end

      it 'limits the expansion to the given models' do
        relation = base.expand_records(child)
        expect(relation.expand_records_values).to eql([child])
      end

      it 'does not add joins without eager loading' do
        result = 'SELECT "activities".*'
        result << ', "activities"."tableoid"::regclass AS _record_class'
        result << ' FROM "activities"'
        expect(base.expand_records.all.to_sql).to eql(result)
      end

      it 'cannot be combined with itself only' do
        expect { base.itself_only.expand_records }.to \
          raise_error(Torque::PostgreSQL::InheritanceError, /itself_only/)
        expect { base.expand_records.itself_only }.to \
          raise_error(Torque::PostgreSQL::InheritanceError, /itself_only/)
      end

      it 'cannot be merged with itself only' do
        expect { base.expand_records.merge(base.itself_only) }.to \
          raise_error(Torque::PostgreSQL::InheritanceError, /itself_only/)
        expect { base.itself_only.merge(base.expand_records) }.to \
          raise_error(Torque::PostgreSQL::InheritanceError, /itself_only/)
      end

      it 'loads the missing columns with one query per table' do
        ActivityPost.create(title: 'Activity post', url: 'posturl1')
        records = nil

        queries = capture_executed_queries do
          records = base.expand_records.order(:id).load.to_a
        end

        expect(queries.size).to eql(3)
        expect(records[1]).to be_instance_of(ActivityBook)
        expect(records[1].url).to eql('bookurl1')
        expect(records[2]).to be_instance_of(ActivityPost)
        expect(records[2].url).to eql('posturl1')
      end

      it 'produces complete and writable records' do
        record = base.expand_records.order(:id).load.to_a[1]

        expect(record.partial_record?).to be_falsey
        expect(record.readonly?).to be_falsey
        expect(record.update!(title: 'Changed')).to be_truthy
      end

      it 'does not leave expanded records dirty' do
        record = base.expand_records.order(:id).load.to_a[1]

        expect(record.changed?).to be_falsey
        expect(record.changes).to be_empty
      end

      it 'only selects the primary key and the extra columns' do
        queries = capture_executed_queries do
          base.expand_records(child).order(:id).load.to_a
        end

        expansion = queries.find { |sql| sql.include?('activity_books') }
        expect(expansion).to match(/SELECT "activity_books"\."id"/)
        expect(expansion).to include('"description"')
        expect(expansion).to include('"url"')
        expect(expansion).not_to include('"title"')
      end

      it 'reads the expansion from only the target table' do
        ActivityPost.create(title: 'Activity post', url: 'posturl1')

        queries = capture_executed_queries do
          base.expand_records(ActivityPost).order(:id).load.to_a
        end

        expansion = queries.find { |sql| sql.include?('activity_posts') }
        expect(expansion).to include('FROM ONLY "activity_posts"')
        expect(expansion).not_to include('_record_class')
      end

      it 'leaves records partial when the inherited row is gone' do
        vanished = child.create(title: 'Vanished book', url: 'bookurl2')
        covered = child.order(:id).first
        row = { 'description' => nil, 'url' => covered.url, 'activated' => nil }
        only_covered = ->(*) { { covered.id => row } }

        allow_any_instance_of(Torque::PostgreSQL::Inheritance::Expander).to \
          receive(:fetch, &only_covered)

        records = base.expand_records.order(:id).load.to_a.last(2)

        expect(records.first.id).to eql(covered.id)
        expect(records.first.partial_record?).to be_falsey
        expect(records.first.url).to eql('bookurl1')

        expect(records.last.id).to eql(vanished.id)
        expect(records.last.partial_record?).to be_truthy
        expect { records.last.url }.to raise_error(ActiveModel::MissingAttributeError)
      end

      it 'preserves an explicit readonly through expansion' do
        record = base.readonly.expand_records.order(:id).load.to_a[1]

        expect(record.url).to eql('bookurl1')
        expect(record.readonly?).to be_truthy
        expect { record.update!(title: 'Changed') }.to \
          raise_error(ActiveRecord::ReadOnlyRecord)
      end
    end
  end

  context 'on associations' do
    let(:author) { Author.create!(name: 'An author name') }

    before :each do
      Activity.create!(title: 'Plain activity', author: author)
      ActivityBook.create!(title: 'A book', url: 'bookurl1', author: author)
      ActivityPost.create!(title: 'A post', url: 'posturl1', author: author)
    end

    it 'returns the correct classes through a preloaded association' do
      activities = Author.includes(:activities).first.activities.sort_by(&:id)

      expect(activities.map(&:class)).to \
        eql([Activity, ActivityBook, ActivityPost])
    end

    it 'leaves preloaded records partial without expanding' do
      activities = Author.includes(:activities).first.activities.sort_by(&:id)

      expect(activities[1].partial_record?).to be_truthy
      expect { activities[1].url }.to raise_error(ActiveModel::MissingAttributeError)
    end

    it 'expands preloaded records when merged' do
      relation = Author.includes(:activities).merge(Activity.expand_records)
      activities = relation.first.activities.sort_by(&:id)

      expect(activities[1]).to be_instance_of(ActivityBook)
      expect(activities[1].url).to eql('bookurl1')
      expect(activities[1].partial_record?).to be_falsey
      expect(activities[1].changed?).to be_falsey
      expect(activities[2].url).to eql('posturl1')
    end

    it 'uses one query per table when expanding through an association' do
      other_author = Author.create!(name: 'Another author name')
      Activity.create!(title: 'Other activity', author: other_author)
      ActivityBook.create!(title: 'Other book', url: 'bookurl2', author: other_author)
      ActivityPost.create!(title: 'Other post', url: 'posturl2', author: other_author)

      queries = capture_executed_queries do
        Author.includes(:activities).merge(Activity.expand_records).load.to_a
      end

      expect(queries.size).to eql(4)
    end

    it 'accumulates targets across repeated cross-model merges' do
      relation = Author.includes(:activities)
        .merge(Activity.expand_records(ActivityBook))
        .merge(Activity.expand_records(ActivityPost))

      expect(relation.expand_records_scoped_value[Activity]).to \
        contain_exactly(ActivityBook, ActivityPost)
    end

    it 'refuses to merge an eager loaded expansion from another model' do
      expect { Author.includes(:activities).merge(Activity.expand_records(eager_load: true)) }.to \
        raise_error(Torque::PostgreSQL::InheritanceError, /eager load/)
    end

    it 'does not raise when a polymorphic association is mixed into the includes' do
      user = User.create!(name: 'A user')
      Comment.create!(user: user, content: 'A comment')

      expect do
        Comment.includes(:commentable).merge(Activity.expand_records).load.to_a
      end.not_to raise_error
    end
  end

  context 'on eager loading' do
    let(:author) { Author.create!(name: 'An author name') }

    let(:post_record) { Post.create!(title: 'A post record', author: author) }

    before :each do
      Activity.create!(title: 'Plain activity', author: author)
      ActivityBook.create!(title: 'A book', url: 'bookurl1', author: author)
      ActivityPost.create!(title: 'A post', url: 'posturl1', author: author, post: post_record)
      ActivityPost::Sample.create!(title: 'A sample', url: 'sampleurl1', author: author)
    end

    it 'casts records the same way includes does' do
      eager = Activity.eager_load(:author).order(:id).to_a
      included = Activity.includes(:author).order(:id).to_a

      expect(eager.map(&:class)).to eql(included.map(&:class))
      expect(eager.map(&:class)).to \
        eql([Activity, ActivityBook, ActivityPost, ActivityPost::Sample])
    end

    it 'leaves eager loaded records partial' do
      record = Activity.eager_load(:author).order(:id).to_a[1]

      expect(record).to be_instance_of(ActivityBook)
      expect(record.partial_record?).to be_truthy
      expect(record.readonly?).to be_truthy
      expect { record.url }.to raise_error(ActiveModel::MissingAttributeError)
    end

    it 'still loads the association without an extra query' do
      record = Activity.eager_load(:author).order(:id).first

      queries = capture_executed_queries { record.author }
      expect(queries).to be_empty
      expect(record.author).to eql(author)
    end

    it 'loads a nested eager load without disturbing the aliasing' do
      queries = capture_executed_queries do
        record = Activity.eager_load(author: :posts).order(:id).load.first

        expect(record).to be_instance_of(Activity)
        expect(record.author).to eql(author)
        expect(record.author.posts.map(&:title)).to eql(['A post record'])
      end

      expect(queries.size).to eql(1)
    end

    it 'loads multiple eager loads without disturbing the aliasing' do
      queries = capture_executed_queries do
        record = ActivityPost.eager_load(:author, :post).order(:id).first

        expect(record).to be_instance_of(ActivityPost)
        expect(record.author).to eql(author)
        expect(record.post.title).to eql('A post record')
      end

      expect(queries.size).to eql(1)
    end

    it 'does not add the marker when the user provides an explicit select' do
      sql = Activity.eager_load(:author).select(:id, :title).to_sql
      expect(sql).not_to include('tableoid')
    end

    it 'does not add the marker when restricted to itself_only' do
      sql = Activity.itself_only.eager_load(:author).to_sql
      expect(sql).not_to include('tableoid')
    end

    it 'does not add the root marker when the root model does not physically inherit' do
      sql = Author.eager_load(:activities).to_sql
      expect(sql).not_to include('_record_class')
    end

    it 'casts an inheriting model loaded as a joined part' do
      records = Author.eager_load(:activities).first.activities.sort_by(&:id)

      expect(records.map(&:class)).to \
        eql([Activity, ActivityBook, ActivityPost, ActivityPost::Sample])
    end

    it 'casts a joined part the same way includes does' do
      eager = Author.eager_load(:activities).first.activities.sort_by(&:id)
      included = Author.includes(:activities).first.activities.sort_by(&:id)

      expect(eager.map(&:class)).to eql(included.map(&:class))
    end

    it 'casts a joined part without any extra query' do
      queries = capture_executed_queries do
        records = Author.eager_load(:activities).to_a.first.activities

        expect(records.map(&:class)).to include(ActivityBook)
      end

      expect(queries.size).to eql(1)
    end

    it 'leaves a casted joined part partial and read-only' do
      record = Author.eager_load(:activities).first.activities.sort_by(&:id)[1]

      expect(record).to be_instance_of(ActivityBook)
      expect(record.partial_record?).to be_truthy
      expect(record.readonly?).to be_truthy
      expect { record.url }.to raise_error(ActiveModel::MissingAttributeError)
    end

    it 'aliases the joined marker using the pattern of the other columns' do
      sql = Author.eager_load(:activities).to_sql

      expect(sql).to match(/"activities"\."tableoid"::regclass AS t1_r\d+/)
      expect(sql.scan('tableoid').size).to eql(1)
    end

    it 'casts both ends when the root inherits as well' do
      record = Activity.eager_load(author: :activities).order(:id).to_a[1]

      expect(record).to be_instance_of(ActivityBook)
      expect(record.author.activities.sort_by(&:id).map(&:class)).to \
        eql([Activity, ActivityBook, ActivityPost, ActivityPost::Sample])
    end

    it 'keeps the joined marker stable when the relation is built twice' do
      relation = Author.eager_load(:activities)
      relation.to_sql

      expect(relation.to_sql.scan('tableoid').size).to eql(1)
      expect(relation.first.activities.map(&:class)).to include(ActivityBook)
    end

    it 'does not add the marker when the relation has an explicit from clause' do
      sql = Activity.from(Activity.itself_only, :activities).eager_load(:author).to_sql
      expect(sql).not_to include('tableoid')
    end

    it 'adds the marker exactly once to the generated sql' do
      sql = Activity.eager_load(:author).to_sql

      expect(sql.scan('_record_class').size).to eql(1)
      expect(sql.scan('tableoid').size).to eql(1)
    end

    it 'casts and fully expands when merged with expand_records, with no extra author query' do
      relation = Activity.eager_load(:author).merge(Activity.expand_records)
      records = relation.order(:id).to_a

      expect(records.map(&:class)).to \
        eql([Activity, ActivityBook, ActivityPost, ActivityPost::Sample])
      expect(records.map(&:partial_record?)).to eql([false, false, false, false])
      expect(records[1].url).to eql('bookurl1')

      queries = capture_executed_queries { records.each(&:author) }
      expect(queries).to be_empty
    end
  end

  context 'on connection' do
    it 'checks the physical inheritance without a permanent connection' do
      expect(ActiveRecord::Base).not_to receive(:connection)

      ActivityPost.remove_instance_variable(:@physically_inherited) \
        if ActivityPost.instance_variable_defined?(:@physically_inherited)
      expect(ActivityPost.physically_inherited?).to be_truthy
    end
  end
end
