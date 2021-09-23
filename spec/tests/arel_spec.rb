require 'spec_helper'

RSpec.describe 'Arel' do
  context 'on inflix operation' do
    let(:list) { Torque::PostgreSQL::Arel::INFLIX_OPERATION }
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
    ].each do |(operator, value, quoted_value)|
      klass_name = operator.to_s.camelize

      context "##{operator}" do
        let(:instance) do
          attribute.public_send(operator, value.is_a?(Array) ? ::Arel.array(value) : value)
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
            expect(result).to be_eql("\"a\".\"sample\" #{list[klass_name]} #{quoted_value}")
          end
        end
      end
    end
  end

  context 'on default value' do
    let(:connection) { ActiveRecord::Base.connection }

    before(:context) { Torque::PostgreSQL.config.use_extended_defaults = true }
    after(:context) { Torque::PostgreSQL.config.use_extended_defaults = false }
    after { Author.reset_column_information }

    it 'does not break jsonb' do
      expect { connection.add_column(:authors, :profile, :jsonb, default: []) }.not_to raise_error
      expect(Author.columns_hash['profile'].default).to eq('[]')
    end

    it 'works properly when column is an array' do
      expect { connection.add_column(:authors, :tag_ids, :bigint, array: true, default: []) }.not_to raise_error
      expect(Author.columns_hash['tag_ids'].default).to eq([])
    end

    it 'works with an array with enum values' do
      value = ['visitor', 'assistant']
      expect { connection.add_column(:authors, :roles, :roles, array: true, default: value) }.not_to raise_error
      expect(Author.columns_hash['roles'].default).to eq(value)
    end

    it 'works with multi dimentional array' do
      value = [['1', '2'], ['3', '4']]
      expect { connection.add_column(:authors, :tag_ids, :string, array: true, default: value) }.not_to raise_error
      expect(Author.columns_hash['tag_ids'].default).to eq(value)
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

      expect(attribute.cast('text').to_sql).to be_eql('"a"."sample"::text')
      expect(quoted.cast('bigint', true).to_sql).to be_eql('ARRAY[1]::bigint[]')
      expect(casted.cast('string').to_sql).to be_eql("1::string")
    end
  end
end
