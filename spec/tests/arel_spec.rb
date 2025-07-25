require 'spec_helper'

RSpec.describe 'Arel' do
  context 'on inflix operation' do
    let(:collector) { ::Arel::Collectors::SQLString }
    let(:attribute) { ::Arel::Table.new('a')['sample'] }
    let(:conn) { ActiveRecord::Base.connection }
    let(:visitor) { ::Arel::Visitors::PostgreSQL.new(conn) }

    [
      [:overlaps,            [1, 2],                       "ARRAY[1, 2]"],
      [:contains,            [3, 4],                       "ARRAY[3, 4]"],
      [:contained_by,        [5, 6],                       "ARRAY[5, 6]"],
      [:has_key,             ::Arel.sql("'a'"),            "'a'"],
      [:has_all_keys,        ['b', 'c'],                   "ARRAY['b', 'c']"],
      [:has_any_keys,        ['d', 'e'],                   "ARRAY['d', 'e']"],

      [:strictly_left,       ::Arel.sql('numrange(1, 2)'), 'numrange(1, 2)'],
      [:strictly_right,      ::Arel.sql('numrange(3, 4)'), 'numrange(3, 4)'],
      [:doesnt_right_extend, ::Arel.sql('numrange(5, 6)'), 'numrange(5, 6)'],
      [:doesnt_left_extend,  ::Arel.sql('numrange(7, 8)'), 'numrange(7, 8)'],
      [:adjacent_to,         ::Arel.sql('numrange(9, 0)'), 'numrange(9, 0)'],
    ].each do |(operation, value, quoted_value)|
      klass_name = operation.to_s.camelize

      context "##{operation}" do
        let(:operator) { instance.operator }
        let(:instance) do
          attribute.public_send(operation, value.is_a?(Array) ? ::Arel.array(value) : value)
        end

        context 'for attribute' do
          let(:klass) { ::Arel::Nodes.const_get(klass_name) }

          it "returns a new #{klass_name}" do
            expect(instance).to be_a(klass)
          end
        end

        context 'for visitor' do
          let(:result) { visitor.accept(instance, collector.new).value }

          it 'returns a formatted operation' do
            expect(result).to be_eql("\"a\".\"sample\" #{operator} #{quoted_value}")
          end
        end
      end
    end
  end

  context 'on default value' do
    let(:connection) { ActiveRecord::Base.connection }

    after { Author.reset_column_information }

    it 'does not break the change column default value method' do
      connection.add_column(:authors, :enabled, :boolean)
      expect { connection.change_column_default(:authors, :enabled, { from: nil, to: true }) }.not_to raise_error
      expect(Author.columns_hash['enabled'].default).to eq('true')
    end

    it 'does not break jsonb' do
      expect { connection.add_column(:authors, :profile, :jsonb, default: []) }.not_to raise_error
      expect(Author.columns_hash['profile'].default).to eq('[]')

      condition = Author.arel_table['profile'].is_distinct_from([])
      expect(Author.where(condition).to_sql).to eq(<<~SQL.squish)
        SELECT "authors".* FROM "authors" WHERE "authors"."profile" IS DISTINCT FROM '[]'
      SQL
    end

    it 'works properly when column is an array' do
      expect { connection.add_column(:authors, :tag_ids, :bigint, array: true, default: []) }.not_to raise_error
      expect(Author.new.tag_ids).to eq([])
    end

    it 'works with an array with enum values for a new enum' do
      value = ['a', 'b']

      expect do
        connection.create_enum(:samples, %i[a b c d])
        connection.add_column(:authors, :samples, :enum, enum_type: :samples, array: true, default: value)
      end.not_to raise_error

      expect(Author.new.samples).to eq(value)
    end

    it 'works with an array with enum values for an existing enum' do
      value = ['visitor', 'assistant']
      expect { connection.add_column(:authors, :roles, :enum, enum_type: :roles, array: true, default: value) }.not_to raise_error
      expect(Author.new.roles).to eq(value)
    end

    it 'works with multi dimentional array' do
      value = [['1', '2'], ['3', '4']]
      expect { connection.add_column(:authors, :tag_ids, :string, array: true, default: value) }.not_to raise_error
      expect(Author.new.tag_ids).to eq(value)
    end

    it 'works with change column default value' do
      value = ['2', '3']
      connection.add_column(:authors, :tag_ids, :string, array: true)
      expect { connection.change_column_default(:authors, :tag_ids, { from: nil, to: value }) }.not_to raise_error
      expect(Author.new.tag_ids).to eq(value)
    end
  end

  context 'on cast' do
    it 'provides an array method' do
      sample1 = ::Arel.array(1, 2, 3, 4)
      sample2 = ::Arel.array([1, 2, 3, 4])
      sample3 = ::Arel.array(1, 2, 3, 4, cast: 'bigint')
      sample4 = ::Arel.array([1, 2, 3, 4], [5, 6, 7, 8], cast: 'integer')

      expect(sample1.to_sql).to be_eql('ARRAY[1, 2, 3, 4]')
      expect(sample2.to_sql).to be_eql('ARRAY[1, 2, 3, 4]')
      expect(sample3.to_sql).to be_eql('ARRAY[1, 2, 3, 4]::bigint[]')
      expect(sample4.to_sql).to be_eql('ARRAY[ARRAY[1, 2, 3, 4], ARRAY[5, 6, 7, 8]]::integer[]')
    end

    it 'provides a cast method' do
      attribute = ::Arel::Table.new('a')['sample']
      quoted = ::Arel::Nodes::build_quoted([1])
      casted = ::Arel::Nodes::build_quoted(1, attribute)

      expect(attribute.pg_cast('text').to_sql).to be_eql('"a"."sample"::text')
      expect(quoted.pg_cast('bigint', true).to_sql).to be_eql('ARRAY[1]::bigint[]')
      expect(casted.pg_cast('string').to_sql).to be_eql("1::string")
    end

    it 'provides proper support to cast methods' do
      attribute = ::Arel::Table.new('a')['sample']
      quoted = ::Arel::Nodes::build_quoted([1])
      casted = ::Arel::Nodes::build_quoted(1)

      expect(attribute.cast('text').to_sql).to be_eql('"a"."sample"::text')
      expect(quoted.cast('bigint', true).to_sql).to be_eql('ARRAY[1]::bigint[]')

      changed_result = ActiveRecord.gem_version >= Gem::Version.new('8.0.2')
      changed_result = changed_result ? 'CAST(1 AS string)' : '1::string'
      expect(casted.pg_cast('string').to_sql).to be_eql("1::string")
    end

    it 'properly works combined on a query' do
      condition = Video.arel_table[:tag_ids].contains([1,2]).cast(:bigint, :array)
      query = Video.all.where(condition).to_sql

      expect(query).to include('WHERE "videos"."tag_ids" @> ARRAY[1, 2]::bigint[]')

      condition = QuestionSelect.arel_table[:options].overlaps(%w[a b]).cast(:string, :array)
      query = QuestionSelect.all.where(condition).to_sql

      expect(query).to include('"options" && ARRAY[\'a\', \'b\']::string[]')
    end
  end
end
