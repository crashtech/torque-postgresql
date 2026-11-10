require 'spec_helper'

RSpec.describe 'CrossJoin' do
  let(:table) { Profile.arel_table }
  let(:snippets) { Torque::PostgreSQL::FN.unnest(table[:snippets]) }

  context 'on model' do
    it 'has its method' do
      expect(Profile).to respond_to(:cross_join)
    end

    it 'returns a relation when using the method' do
      expect(Profile.cross_join(snippets, as: :doc)).to be_a(ActiveRecord::Relation)
    end
  end

  context 'on relation' do
    subject { Profile.unscoped }

    it 'has its method' do
      expect(subject).to respond_to(:cross_join)
    end

    it 'joins an arel function without naming its columns' do
      expect(subject.cross_join(snippets, as: :doc).to_sql).to \
        eql('SELECT "profiles".* FROM "profiles" CROSS JOIN UNNEST("profiles"."snippets") "doc"')
    end

    it 'names the columns when they are given' do
      expect(subject.cross_join(snippets, as: :doc, columns: %i[value]).to_sql).to \
        eql('SELECT "profiles".* FROM "profiles" CROSS JOIN UNNEST("profiles"."snippets") "doc"("value")')
    end

    it 'does not write LATERAL for a function' do
      expect(subject.cross_join(snippets, as: :doc).to_sql).not_to include('LATERAL')
    end

    it 'does not write ROWS FROM without an ordinality' do
      expect(subject.cross_join(snippets, as: :doc).to_sql).not_to include('ROWS FROM')
    end

    it 'raises for a source it cannot join' do
      expect { subject.cross_join('whatever', as: :doc) }.to \
        raise_error(ArgumentError, /Unable to join/)
    end
  end

  context 'modes' do
    subject { Profile.unscoped }

    it 'writes a left join against a true condition' do
      expect(subject.cross_join(snippets, as: :doc, mode: :left).to_sql).to \
        eql('SELECT "profiles".* FROM "profiles" LEFT OUTER JOIN UNNEST("profiles"."snippets") "doc" ON TRUE')
    end

    it 'raises for a mode postgres cannot combine with a lateral reference' do
      expect { subject.cross_join(snippets, as: :doc, mode: :right) }.to \
        raise_error(ArgumentError, /not implemented as a join type/)
    end
  end

  context 'rows' do
    subject { Profile.unscoped }

    it 'turns a list of documents into one array per column' do
      result = subject.cross_join([{ id: 1, label: 'a' }, { id: 2, label: 'b' }], as: :v)
      expect(result.to_sql).to \
        eql('SELECT "profiles".* FROM "profiles" CROSS JOIN UNNEST(ARRAY[1, 2], ARRAY[\'a\', \'b\']) "v"("id", "label")')
    end

    it 'accepts plain rows when the columns are named' do
      result = subject.cross_join([[1, 'a']], as: :v, columns: %i[id label])
      expect(result.to_sql).to \
        eql('SELECT "profiles".* FROM "profiles" CROSS JOIN UNNEST(ARRAY[1], ARRAY[\'a\']) "v"("id", "label")')
    end

    it 'reads the documents by name, in any order' do
      result = subject.cross_join([{ id: 1, label: 'a' }, { label: 'b', id: 2 }], as: :v)
      expect(result.to_sql).to \
        eql('SELECT "profiles".* FROM "profiles" CROSS JOIN UNNEST(ARRAY[1, 2], ARRAY[\'a\', \'b\']) "v"("id", "label")')
    end

    it 'does not care whether the keys are strings or symbols' do
      result = subject.cross_join([{ 'id' => 1 }], as: :v, columns: %i[id])
      expect(result.to_sql).to include('UNNEST(ARRAY[1]) "v"("id")')
    end

    it 'raises when the columns cannot be named' do
      expect { subject.cross_join([[1, 'a']], as: :v) }.to \
        raise_error(ArgumentError, /Unable to name the columns/)
    end

    it 'raises for an empty list' do
      expect { subject.cross_join([], as: :v) }.to \
        raise_error(ArgumentError, /empty list/)
    end

    it 'multiplies the rows of the query' do
      Profile.create!(name: 'one')
      Profile.create!(name: 'two')

      expect(subject.cross_join([{ n: 1 }, { n: 2 }, { n: 3 }], as: :v).count).to be_eql(6)
    end

    it 'keeps the values typed' do
      Profile.create!(name: 'one')
      result = subject.cross_join([{ n: 10 }], as: :v).pluck(Arel.sql('"v"."n"'))

      expect(result).to be_eql([10])
    end
  end

  context 'a relation' do
    subject { Profile.unscoped }

    it 'is written as a lateral subquery' do
      other = Profile.select(:name).limit(1)
      expect(subject.cross_join(other, as: :other, columns: %i[name]).to_sql).to \
        include('CROSS JOIN LATERAL (SELECT "profiles"."name" FROM "profiles" LIMIT 1) "other"("name")')
    end

    it 'keeps the bindings of both queries apart' do
      Profile.create!(name: 'aaa')
      Profile.create!(name: 'bbb')

      other = Profile.where(name: 'aaa').select(:name).limit(1)
      result = subject.where(name: 'bbb').cross_join(other, as: :other, columns: %i[name])

      expect(result.pluck(:name, Arel.sql('"other"."name"'))).to be_eql([%w[bbb aaa]])
    end
  end

  context 'with_ordinality' do
    subject { Profile.unscoped }

    it 'uses the configured name' do
      expect(subject.cross_join(snippets, as: :doc, columns: %i[value], with_ordinality: true).to_sql).to \
        eql('SELECT "profiles".* FROM "profiles" CROSS JOIN UNNEST("profiles"."snippets")' \
          ' WITH ORDINALITY "doc"("value", "ordinality")')
    end

    it 'accepts a name of its own' do
      expect(subject.cross_join(snippets, as: :doc, columns: %i[value], with_ordinality: :idx).to_sql).to \
        eql('SELECT "profiles".* FROM "profiles" CROSS JOIN UNNEST("profiles"."snippets")' \
          ' WITH ORDINALITY "doc"("value", "idx")')
    end

    it 'leaves the list out when the columns are unknown' do
      result = subject.cross_join(snippets, as: :doc, with_ordinality: true).to_sql
      expect(result).to end_with('WITH ORDINALITY "doc"')
    end

    it 'refuses a name of its own when the columns are unknown' do
      expect { subject.cross_join(snippets, as: :doc, with_ordinality: :idx) }.to \
        raise_error(ArgumentError, /columns of the source are unknown/)
    end

    it 'counts from one, in the order of the list' do
      Profile.create!(name: 'one')
      result = subject.cross_join([{ n: 'a' }, { n: 'b' }, { n: 'c' }], as: :v, with_ordinality: true)

      expect(result.pluck(Arel.sql('"v"."ordinality"'))).to be_eql([1, 2, 3])
    end
  end

  context 'scoping' do
    subject { Profile.unscoped.cross_join(snippets, as: :doc) }

    it 'is removed by unscope' do
      expect(subject.unscope(:cross_joins).to_sql).to eql('SELECT "profiles".* FROM "profiles"')
    end

    it 'is removed by except' do
      expect(subject.except(:cross_joins).to_sql).to eql('SELECT "profiles".* FROM "profiles"')
    end

    it 'is carried over by merge' do
      expect(Profile.all.merge(subject).to_sql).to include('CROSS JOIN UNNEST')
    end

    it 'is not removed by except(:joins)' do
      expect(subject.except(:joins).to_sql).to include('CROSS JOIN UNNEST')
    end
  end
end
