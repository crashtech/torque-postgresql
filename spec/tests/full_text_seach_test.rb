require 'spec_helper'

RSpec.describe 'FullTextSearch' do
  context 'on builder' do
    let(:builder) { Torque::PostgreSQL::Attributes::Builder }

    describe '.to_search_weights' do
      it 'works with a single column' do
        expect(builder.to_search_weights('title')).to eq({ 'title' => 'A' })
        expect(builder.to_search_weights(:title)).to eq({ 'title' => 'A' })
      end

      it 'works with an array of columns' do
        value = { 'title' => 'A', 'content' => 'B' }
        expect(builder.to_search_weights(%w[title content])).to eq(value)
        expect(builder.to_search_weights(%i[title content])).to eq(value)
      end

      it 'works with a hash of columns and weights' do
        value = { 'title' => 'A', 'content' => 'B', 'summary' => 'C' }
        expect(builder.to_search_weights(value.transform_keys(&:to_sym))).to eq(value)
      end

      it 'works with a hash of columns and invalid weights' do
        value = { 'title' => 'X', 'content' => 'Y', 'summary' => 'Z' }
        expect(builder.to_search_weights(value.transform_keys(&:to_sym))).to eq(value)
      end
    end

    describe '.to_search_vector_operation' do
      it 'builds a simple one' do
        result = builder.to_search_vector_operation('english', { 'title' => 'A' })
        expect(result.to_sql).to eq("TO_TSVECTOR('english', COALESCE(title, ''))")
      end

      it 'builds with 2 columns' do
        columns = { 'title' => 'A', 'content' => 'B' }
        result = builder.to_search_vector_operation('english', columns)
        expect(result.to_sql).to eq(<<~SQL.squish)
          SETWEIGHT(TO_TSVECTOR('english', COALESCE(title, '')), 'A') ||
          SETWEIGHT(TO_TSVECTOR('english', COALESCE(content, '')), 'B')
        SQL
      end

      it 'builds with a dynamic language' do
        columns = { 'title' => 'A', 'content' => 'B' }
        result = builder.to_search_vector_operation(:lang, columns)
        expect(result.to_sql).to eq(<<~SQL.squish)
          SETWEIGHT(TO_TSVECTOR(lang, COALESCE(title, '')), 'A') ||
          SETWEIGHT(TO_TSVECTOR(lang, COALESCE(content, '')), 'B')
        SQL
      end
    end

    describe '.search_vector_options' do
      it 'correctly translates the settings' do
        options = builder.search_vector_options(columns: 'title')
        expect(options).to eq(
          type: :tsvector,
          as: "TO_TSVECTOR('english', COALESCE(title, ''))",
          stored: true,
        )
      end

      it 'properly adds the index type' do
        options = builder.search_vector_options(columns: 'title', index: true)
        expect(options).to eq(
          type: :tsvector,
          as: "TO_TSVECTOR('english', COALESCE(title, ''))",
          stored: true,
          index: { using: :gin },
        )
      end
    end
  end

  context 'on schema dumper' do
    let(:connection) { ActiveRecord::Base.connection }
    let(:source) { ActiveRecord::Base.connection_pool }
    let(:dump_result) do
      ActiveRecord::SchemaDumper.dump(source, (dump_result = StringIO.new))
      dump_result.string
    end

    it 'properly supports search language' do
      parts = %{t.search_language "lang", default: "english", null: false}
      expect(dump_result).to include(parts)
    end

    it 'properly translates a simple single search vector with embedded language' do
      parts = 't.search_vector "search_vector", stored: true'
      parts << ', language: :lang, columns: :title'
      expect(dump_result).to include(parts)
    end

    it 'properly translates a simple multiple column search vector with language' do
      parts = 't.search_vector "search_vector", stored: true'
      parts << ', language: "english", columns: [:title, :content]'
      expect(dump_result).to include(parts)
    end

    it 'supports a custom definition of weights' do
      connection.create_table :custom_search do |t|
        t.string :title
        t.string :content
        t.string :subtitle
        t.search_vector :sample_a, columns: {
          title: 'A',
          subtitle: 'A',
          content: 'B',
        }
        t.search_vector :sample_b, columns: {
          title: 'A',
          subtitle: 'C',
          content: 'D',
        }
        t.search_vector :sample_c, columns: {
          title: 'C',
          subtitle: 'B',
          content: 'A',
        }
      end

      parts = 't.search_vector "sample_a", stored: true'
      parts << ', language: "english", columns: { title: "A", subtitle: "A", content: "B" }'
      expect(dump_result).to include(parts)

      parts = 't.search_vector "sample_b", stored: true'
      parts << ', language: "english", columns: { title: "A", subtitle: "C", content: "D" }'
      expect(dump_result).to include(parts)

      parts = 't.search_vector "sample_c", stored: true'
      parts << ', language: "english", columns: [:content, :subtitle, :title]'
      expect(dump_result).to include(parts)
    end
  end

  context 'on config' do
    let(:base) { Course }
    let(:scope) { 'full_text_search' }

    let(:mod) { base.singleton_class.included_modules.first }

    after { mod.send(:undef_method, scope) if scope.present? }

    it 'has the initialization method' do
      scope.replace('')
      expect(base).to respond_to(:torque_search_for)
    end

    it 'properly generates the search scope' do
      base.torque_search_for(:search_vector)
      expect(base.all).to respond_to(:full_text_search)
    end

    it 'works with prefix and suffix' do
      scope.replace('custom_full_text_search_scope')
      base.torque_search_for(:search_vector, prefix: 'custom', suffix: 'scope')
      expect(base.all).to respond_to(:custom_full_text_search_scope)
    end
  end

  context 'on relation' do
    let(:base) { Course }
    let(:scope) { 'full_text_search' }

    let(:mod) { base.singleton_class.included_modules.first }

    before { Course.torque_search_for(:search_vector) }
    after { mod.send(:undef_method, :full_text_search) }

    it 'performs a simple query' do
      result = Course.full_text_search('test')
      parts = 'SELECT "courses".* FROM "courses"'
      parts << ' WHERE "courses"."search_vector" @@'
      parts << " PHRASETO_TSQUERY('english', 'test')"
      expect(result.to_sql).to eql(parts)
    end

    it 'can include the order' do
      result = Course.full_text_search('test', order: true)
      parts = 'SELECT "courses".* FROM "courses"'
      parts << ' WHERE "courses"."search_vector" @@'
      parts << " PHRASETO_TSQUERY('english', 'test')"
      parts << ' ORDER BY TS_RANK("courses"."search_vector",'
      parts << " PHRASETO_TSQUERY('english', 'test')) ASC"
      expect(result.to_sql).to eql(parts)
    end

    it 'can include the order descending' do
      result = Course.full_text_search('test', order: :desc)
      parts = 'SELECT "courses".* FROM "courses"'
      parts << ' WHERE "courses"."search_vector" @@'
      parts << " PHRASETO_TSQUERY('english', 'test')"
      parts << ' ORDER BY TS_RANK("courses"."search_vector",'
      parts << " PHRASETO_TSQUERY('english', 'test')) DESC"
      expect(result.to_sql).to eql(parts)
    end

    it 'can include the rank' do
      result = Course.full_text_search('test', rank: true)
      parts = 'SELECT "courses".*, TS_RANK("courses"."search_vector",'
      parts << " PHRASETO_TSQUERY('english', 'test')) AS rank"
      parts << ' FROM "courses" WHERE "courses"."search_vector" @@'
      parts << " PHRASETO_TSQUERY('english', 'test')"
      expect(result.to_sql).to eql(parts)
    end

    it 'can include the rank named differently' do
      result = Course.full_text_search('test', rank: :custom_rank)
      parts = 'SELECT "courses".*, TS_RANK("courses"."search_vector",'
      parts << " PHRASETO_TSQUERY('english', 'test')) AS custom_rank"
      parts << ' FROM "courses" WHERE "courses"."search_vector" @@'
      parts << " PHRASETO_TSQUERY('english', 'test')"
      expect(result.to_sql).to eql(parts)
    end

    it 'can use regular query mode' do
      result = Course.full_text_search('test', phrase: false)
      parts = 'SELECT "courses".* FROM "courses"'
      parts << ' WHERE "courses"."search_vector" @@'
      parts << " TO_TSQUERY('english', 'test')"
      expect(result.to_sql).to eql(parts)
    end

    it 'can use a attribute as the language' do
      result = Course.full_text_search('test', language: :lang)
      parts = 'SELECT "courses".* FROM "courses"'
      parts << ' WHERE "courses"."search_vector" @@'
      parts << %{ PHRASETO_TSQUERY("courses"."lang", 'test')}
      expect(result.to_sql).to eql(parts)
    end

    it 'can call a method to pull the language' do
      Course.define_singleton_method(:search_language) { 'portuguese' }
      result = Course.full_text_search('test', language: :search_language)
      parts = 'SELECT "courses".* FROM "courses"'
      parts << ' WHERE "courses"."search_vector" @@'
      parts << " PHRASETO_TSQUERY('portuguese', 'test')"
      expect(result.to_sql).to eql(parts)
      Course.singleton_class.undef_method(:search_language)
    end

    it 'properly binds all provided values' do
      query = Course.full_text_search('test')
      sql, binds = get_query_with_binds { query.load }
      expect(sql).to include("PHRASETO_TSQUERY($1, $2)")
      expect(binds.first.value).to eq('english')
      expect(binds.second.value).to eq('test')
    end
  end
end
