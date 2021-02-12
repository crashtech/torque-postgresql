require 'spec_helper'

RSpec.describe 'InsertAll' do
  context 'on executing' do
    before do
      ActiveRecord::InsertAll.send(:public, :to_sql)
      allow_any_instance_of(ActiveRecord::InsertAll).to receive(:execute, &:to_sql)
    end

    subject { Tag }

    let(:entries) { [{ name: 'A' }, { name: 'B' }] }

    it 'does not mess with insert_all' do
      result = subject.insert_all(entries)
      expect(result.squish).to be_eql(<<~SQL.squish)
        INSERT INTO "tags" ("name") VALUES ('A'), ('B')
        ON CONFLICT  DO NOTHING RETURNING "id"
      SQL

      result = subject.insert_all(entries, returning: :name)
      expect(result.squish).to be_eql(<<~SQL.squish)
        INSERT INTO "tags" ("name") VALUES ('A'), ('B')
        ON CONFLICT  DO NOTHING RETURNING name
      SQL

      result = subject.insert_all(entries, returning: %i[id name])
      expect(result.squish).to be_eql(<<~SQL.squish)
        INSERT INTO "tags" ("name") VALUES ('A'), ('B')
        ON CONFLICT  DO NOTHING RETURNING "id","name"
      SQL

      result = subject.insert_all(entries, unique_by: :id)
      expect(result.squish).to be_eql(<<~SQL.squish)
        INSERT INTO "tags" ("name") VALUES ('A'), ('B')
        ON CONFLICT ("id") DO NOTHING RETURNING "id"
      SQL
    end

    it 'does not mess with insert_all!' do
      result = subject.insert_all!(entries)
      expect(result.squish).to be_eql(<<~SQL.squish)
        INSERT INTO "tags" ("name") VALUES ('A'), ('B') RETURNING "id"
      SQL

      result = subject.insert_all!(entries, returning: :name)
      expect(result.squish).to be_eql(<<~SQL.squish)
        INSERT INTO "tags" ("name") VALUES ('A'), ('B') RETURNING name
      SQL
    end

    it 'does not mess with upsert without where' do
      result = subject.upsert_all(entries)
      expect(result.squish).to be_eql(<<~SQL.squish)
        INSERT INTO "tags" ("name") VALUES ('A'), ('B')
        ON CONFLICT ("id") DO UPDATE SET "name"=excluded."name"
        RETURNING "id"
      SQL

      result = subject.upsert_all(entries, returning: :name)
      expect(result.squish).to be_eql(<<~SQL.squish)
        INSERT INTO "tags" ("name") VALUES ('A'), ('B')
        ON CONFLICT ("id") DO UPDATE SET "name"=excluded."name"
        RETURNING name
      SQL
    end

    it 'does add the where condition without the returning clause' do
      result = subject.upsert_all(entries, returning: false, where: '1=1')
      expect(result.squish).to be_eql(<<~SQL.squish)
        INSERT INTO "tags" ("name") VALUES ('A'), ('B')
        ON CONFLICT ("id") DO UPDATE SET "name"=excluded."name"
        WHERE 1=1
      SQL
    end

    it 'does add the where condition with the returning clause' do
      result = subject.upsert_all(entries, where: '1=1')
      expect(result.squish).to be_eql(<<~SQL.squish)
        INSERT INTO "tags" ("name") VALUES ('A'), ('B')
        ON CONFLICT ("id") DO UPDATE SET "name"=excluded."name"
        WHERE 1=1 RETURNING "id"
      SQL
    end

    xit 'dows work with model-based where clause' do
      result = subject.upsert_all(entries, where: Tag.where(name: 'C'))
      expect(result.squish).to be_eql(<<~SQL.squish)
        INSERT INTO "tags" ("name") VALUES ('A'), ('B')
        ON CONFLICT ("id") DO UPDATE SET "name"=excluded."name"
        WHERE "tags"."name" = 'C' RETURNING "id"
      SQL
    end
  end
end
