require 'spec_helper'

RSpec.describe 'Schema' do
  let(:connection) { ActiveRecord::Base.connection }

  before do
    connection.instance_variable_set(:@schmeas_blacklist, nil)
    connection.instance_variable_set(:@schmeas_whitelist, nil)
  end

  context 'on migration' do
    it 'can check for existance' do
      expect(connection.schema_exists?(:information_schema)).to be_falsey
      expect(connection.schema_exists?(:information_schema, filtered: false)).to be_truthy
    end

    it 'can be created' do
      expect(connection.schema_exists?(:legacy, filtered: false)).to be_falsey
      connection.create_schema(:legacy)
      expect(connection.schema_exists?(:legacy, filtered: false)).to be_truthy
    end

    it 'can be deleted' do
      expect(connection.schema_exists?(:legacy, filtered: false)).to be_falsey

      connection.create_schema(:legacy)
      expect(connection.schema_exists?(:legacy, filtered: false)).to be_truthy

      connection.drop_schema(:legacy)
      expect(connection.schema_exists?(:legacy, filtered: false)).to be_falsey
    end

    it 'works with whitelist' do
      expect(connection.schema_exists?(:legacy)).to be_falsey
      connection.create_schema(:legacy)

      expect(connection.schema_exists?(:legacy)).to be_falsey
      expect(connection.schema_exists?(:legacy, filtered: false)).to be_truthy

      connection.schemas_whitelist.push('legacy')
      expect(connection.schema_exists?(:legacy)).to be_truthy
    end
  end

  context 'on schema' do
    let(:dump_result) do
      ActiveRecord::SchemaDumper.dump(connection, (dump_result = StringIO.new))
      dump_result.string
    end

    it 'does not add when there is no extra schemas' do
      connection.drop_schema(:internal, force: :cascade)
      expect(dump_result).not_to match /Custom schemas defined in this database/
    end

    it 'does not include tables from blacklisted schemas' do
      connection.schemas_blacklist.push('internal')
      expect(dump_result).not_to match /create_table \"users\",.*schema: +"internal"/
    end

    context 'with internal schema whitelisted' do
      before { connection.schemas_whitelist.push('internal') }

      it 'dumps the schemas' do
        expect(dump_result).to match /create_schema \"internal\"/
      end

      it 'shows the internal users table in the connection tables list' do
        expect(connection.tables).to include('internal.users')
      end

      it 'dumps tables on whitelisted schemas' do
        expect(dump_result).to match /create_table \"users\",.*schema: +"internal"/
      end
    end
  end

  context 'on relation' do
    let(:model) { Internal::User }

    it 'adds the schema to the query' do
      expect(model.all.to_sql).to match(/FROM "internal"."users"/)
    end

    it 'can load the schema from the module' do
      allow(Internal).to receive(:schema).and_return('internal')
      allow(model).to receive(:schema).and_return(nil)

      expect(model.all.to_sql).to match(/FROM "internal"."users"/)
    end
  end
end
