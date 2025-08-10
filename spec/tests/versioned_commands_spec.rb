require 'spec_helper'

RSpec.describe 'VersionedCommands' do
  let(:connection) { ActiveRecord::Base.connection }

  context 'on migration' do
    it 'does not have any of the schema methods' do
      expect(connection).not_to respond_to(:create_function)
      expect(connection).not_to respond_to(:create_type)
      expect(connection).not_to respond_to(:create_view)
    end

    it 'does not have the methods available in a migration' do
      instance = Class.new(ActiveRecord::Migration::Current).allocate
      expect(instance).not_to respond_to(:create_function)
      expect(instance).not_to respond_to(:create_type)
      expect(instance).not_to respond_to(:create_view)
    end

    it 'does have the methods in schema definition' do
      instance = ActiveRecord::Schema[ActiveRecord::Migration.current_version].allocate
      expect(instance).to respond_to(:create_function)
      expect(instance).to respond_to(:create_type)
      expect(instance).to respond_to(:create_view)
    end

    context 'on context' do
      let(:context) { connection.pool.migration_context }
      let(:path) { Pathname.new(__FILE__).join('../../fixtures/migrations').expand_path.to_s }

      before { context.instance_variable_set(:@migrations_paths, [path]) }

      it 'list all migrations accordingly' do
        result = context.migrations.map { |m| File.basename(m.filename) }
        expect(result[0]).to eq('20250101000001_create_users.rb')
        expect(result[1]).to eq('20250101000002_create_function_count_users_v1.sql')
        expect(result[2]).to eq('20250101000003_create_internal_users.rb')
        expect(result[3]).to eq('20250101000004_update_function_count_users_v2.sql')
        expect(result[4]).to eq('20250101000005_create_view_all_users_v1.sql')
        expect(result[5]).to eq('20250101000006_create_type_user_id_v1.sql')
        expect(result[6]).to eq('20250101000007_remove_function_count_users_v2.sql')
      end

      it 'correctly report the status of all migrations' do
        result = context.migrations_status.reject { |s| s[1].start_with?('0') }
        expect(result[0]).to eq(['down', '20250101000001', 'Create users'])
        expect(result[1]).to eq(['down', '20250101000002', 'Create Function count_users (v1)'])
        expect(result[2]).to eq(['down', '20250101000003', 'Create internal users'])
        expect(result[3]).to eq(['down', '20250101000004', 'Update Function count_users (v2)'])
        expect(result[4]).to eq(['down', '20250101000005', 'Create View all_users (v1)'])
        expect(result[5]).to eq(['down', '20250101000006', 'Create Type user_id (v1)'])
        expect(result[6]).to eq(['down', '20250101000007', 'Remove Function count_users (v2)'])
      end

      it 'reports for invalid names' do
        allow(context).to receive(:command_files).and_return(['something.sql'])
        error = ::Torque::PostgreSQL::IllegalCommandTypeError
        expect { context.migrations }.to raise_error(error)
      end
    end

    context 'on validation' do
      let(:base) { Torque::PostgreSQL::VersionedCommands }

      context 'on function' do
        it 'prevents multiple functions definition' do
          content = <<~SQL
            CREATE FUNCTION test(a integer);
            CREATE FUNCTION other_test(a varchar);
          SQL

          expect do
            base.validate!(:function, content, 'test')
          end.to raise_error(ArgumentError)
        end

        it 'prevents same name but different schema' do
          content = <<~SQL
            CREATE FUNCTION internal.test(a integer);
            CREATE FUNCTION external.test(a varchar);
          SQL

          expect do
            base.validate!(:function, content, 'test')
          end.to raise_error(ArgumentError)
        end

        it 'requires OR REPLACE clause' do
          content = <<~SQL
            CREATE OR REPLACE FUNCTION test(a integer);
            CREATE FUNCTION test(a varchar);
          SQL

          expect do
            base.validate!(:function, content, 'test')
          end.to raise_error(ArgumentError)
        end

        it 'requires matching name' do
          content = <<~SQL
            CREATE OR REPLACE FUNCTION other_test(a integer);
            CREATE OR REPLACE FUNCTION other_test(a varchar);
          SQL

          expect do
            base.validate!(:function, content, 'test')
          end.to raise_error(ArgumentError)
        end

        it 'works when setup correctly' do
          content = <<~SQL
            CREATE OR REPLACE FUNCTION test(a integer);
            CREATE OR REPLACE FUNCTION test(a varchar);
            CREATE OR REPLACE FUNCTION TEST(a date);
          SQL

          expect { base.validate!(:function, content, 'test') }.not_to raise_error
        end

        it 'supports name with schema' do
          content = <<~SQL
            CREATE OR REPLACE FUNCTION internal.test(a integer);
            CREATE OR REPLACE FUNCTION internal.test(a varchar);
            CREATE OR REPLACE FUNCTION internal.TEST(a date);
          SQL

          expect { base.validate!(:function, content, 'internal_test') }.not_to raise_error
        end
      end

      context 'on type' do
        it 'prevents multiple type definitions' do
          content = <<~SQL
            CREATE TYPE test AS;
            CREATE TYPE other_test AS;
          SQL

          expect do
            base.validate!(:type, content, 'test')
          end.to raise_error(ArgumentError)
        end

        it 'prevents same name but different schema' do
          content = <<~SQL
            DROP TYPE IF EXISTS internal.test;
            CREATE TYPE external.test AS;
          SQL

          expect do
            base.validate!(:type, content, 'test')
          end.to raise_error(ArgumentError)
        end

        it 'prevents multiple type drops' do
          content = <<~SQL
            DROP TYPE IF EXISTS test;
            DROP TYPE IF EXISTS other_test;
            CREATE TYPE test AS;
          SQL

          expect do
            base.validate!(:type, content, 'test')
          end.to raise_error(ArgumentError)
        end

        it 'requires DROP TYPE clause' do
          content = <<~SQL
            CREATE TYPE test AS;
          SQL

          expect do
            base.validate!(:type, content, 'test')
          end.to raise_error(ArgumentError)
        end

        it 'prevents dropping other types' do
          content = <<~SQL
            DROP TYPE IF EXISTS other_test;
            CREATE TYPE test AS;
          SQL

          expect do
            base.validate!(:type, content, 'test')
          end.to raise_error(ArgumentError)
        end

        it 'requires matching name' do
          content = <<~SQL
            DROP TYPE IF EXISTS other_test;
            CREATE TYPE other_test AS;
          SQL

          expect do
            base.validate!(:type, content, 'test')
          end.to raise_error(ArgumentError)
        end

        it 'works when setup correctly' do
          content = <<~SQL
            DROP TYPE IF EXISTS test;
            CREATE TYPE TEST AS;
          SQL

          expect { base.validate!(:type, content, 'test') }.not_to raise_error
        end

        it 'supports name with schema' do
          content = <<~SQL
            DROP TYPE IF EXISTS internal.test;
            CREATE TYPE INTERNAL.TEST AS;
          SQL

          expect { base.validate!(:type, content, 'internal_test') }.not_to raise_error
        end
      end

      context 'on view' do
        it 'requires a proper definition' do
          content = <<~SQL
            CREATE TEMP MATERIALIZED VIEW test AS;
          SQL

          expect do
            base.validate!(:view, content, 'test')
          end.to raise_error(ArgumentError)
        end
        it 'prevents multiple view definitions' do
          content = <<~SQL
            CREATE VIEW test AS;
            CREATE VIEW other_test AS;
          SQL

          expect do
            base.validate!(:view, content, 'test')
          end.to raise_error(ArgumentError)
        end

        it 'requires OR REPLACE clause' do
          content = <<~SQL
            CREATE VIEW test AS;
          SQL

          expect do
            base.validate!(:view, content, 'test')
          end.to raise_error(ArgumentError)
        end

        it 'requires matching name' do
          content = <<~SQL
            CREATE OR REPLACE VIEW other_test AS;
          SQL

          expect do
            base.validate!(:view, content, 'test')
          end.to raise_error(ArgumentError)
        end

        it 'works when setup correctly' do
          content = <<~SQL
            CREATE OR REPLACE VIEW TEST AS;
          SQL

          expect { base.validate!(:view, content, 'test') }.not_to raise_error
        end

        it 'supports materialized views' do
          content = <<~SQL
            DROP MATERIALIZED VIEW IF EXISTS test;
            CREATE MATERIALIZED VIEW test AS;
          SQL

          expect { base.validate!(:view, content, 'test') }.not_to raise_error
        end

        it 'supports name with schema' do
          content = <<~SQL
            CREATE OR REPLACE VIEW internal.test AS;
          SQL

          expect { base.validate!(:view, content, 'internal_test') }.not_to raise_error
        end
      end
    end

    context 'on running' do
      let(:base) { Torque::PostgreSQL::VersionedCommands }
      let(:sql) { 'CREATE TYPE test;' }
      let(:command) do
        base::CommandMigration.new('test.sql', 1, 'create', 'type', 'test', 1)
      end

      before do
        allow_any_instance_of(ActiveRecord::Migration).to receive(:puts) # Disable messages

        allow(File).to receive(:expand_path, &:itself)
        allow(File).to receive(:read).with('test.sql').and_return(sql)

        # Validations are better tested above
        allow(base).to receive(:validate!).and_return(true)
      end

      it 'has the right name' do
        expect(command.name).to eq('create_type_test_v1')
      end

      it 'creates the type properly' do
        expect(connection).to receive(:execute).with(sql)
        command.migrate(:up)
      end

      it 'reverts to the previous file' do
        sql2 = 'CREATE TYPE test_v1;'
        command.op_version = 2
        expect(base).to receive(:fetch_command).with(Array, 'type', 'test', 1).and_return(sql2)
        expect(connection).to receive(:execute).with(sql2)
        command.migrate(:down)
      end

      it 'reverts to the same version when reverting a remove' do
        command.op = 'remove'
        command.op_version = 2
        expect(base).to receive(:fetch_command).with(Array, 'type', 'test', 2).and_return(sql)
        expect(connection).to receive(:execute).with(sql)
        command.migrate(:down)
      end

      it 'properly drops functions' do
        command.type = 'function'

        sql.replace('CREATE FUNCTION test;')
        expect(connection).to receive(:execute).with('DROP FUNCTION test;')
        command.migrate(:down)

        sql.replace('CREATE FUNCTION test();')
        expect(connection).to receive(:execute).with('DROP FUNCTION test();')
        command.migrate(:down)

        sql.replace('CREATE FUNCTION test(int); CREATE FUNCTION test(float);')
        expect(connection).to receive(:execute).with('DROP FUNCTION test(int), test(float);')
        command.migrate(:down)
      end

      it 'properly drops types' do
        command.type = 'type'

        sql.replace('CREATE TYPE test;')
        expect(connection).to receive(:execute).with('DROP TYPE test;')
        command.migrate(:down)
      end

      it 'properly drops views' do
        command.type = 'view'

        sql.replace('CREATE VIEW test AS SELECT 1;')
        expect(connection).to receive(:execute).with('DROP VIEW test;')
        command.migrate(:down)

        sql.replace('CREATE MATERIALIZED VIEW test AS SELECT 1;')
        expect(connection).to receive(:execute).with('DROP MATERIALIZED VIEW test;')
        command.migrate(:down)

        sql.replace('CREATE RECURSIVE VIEW test AS SELECT 1;')
        expect(connection).to receive(:execute).with('DROP VIEW test;')
        command.migrate(:down)
      end
    end

    context 'on migrator' do
      let(:base) { Torque::PostgreSQL::VersionedCommands }
      let(:table) { base::SchemaTable.new(connection.pool) }
      let(:context) { connection.pool.migration_context }
      let(:versions) { migrations.map(&:version).map(&:to_i) }
      let(:migrations) { [ActiveRecord::Migration.new('base', 1)] }

      before do
        allow_any_instance_of(ActiveRecord::Migration).to receive(:puts) # Disable messages
        allow(File).to receive(:expand_path, &:itself)

        # Validations are better tested above
        allow(base).to receive(:validate!).and_return(true)
        allow(context).to receive(:migrations).and_return(migrations)
        allow(context.schema_migration).to receive(:integer_versions).and_return(versions)
      end

      it 'expect the table to not exist by default' do
        expect(table.table_exists?).to be_falsey
      end

      it 'creates the table on first migration' do
        migration('CREATE TYPE test;')

        expect(table.table_exists?).to be_falsey
        context.up(2)
        expect(table.table_exists?).to be_truthy
        expect(table.count).to eq(1)
        expect(table.versions_of('type')).to eq([['test_2', 1]])
      end

      it 'drops the table if all versions are removed' do
        migrations << ActiveRecord::Migration.new('other', 2)
        versions << 2

        migration('CREATE TYPE test;')

        expect(table.table_exists?).to be_falsey
        context.up(3)
        expect(table.table_exists?).to be_truthy
        expect(table.count).to eq(1)

        versions << 3
        context.down(2)
        expect(table.table_exists?).to be_falsey
        expect(table.count).to eq(0)
      end

      it 'does no drop the table if there are still records' do
        migration('CREATE TYPE test;')
        migration('CREATE TYPE other;')

        expect(table.table_exists?).to be_falsey
        context.up(3)
        expect(table.table_exists?).to be_truthy
        expect(table.count).to eq(2)

        versions << 2
        versions << 3
        context.down(2)
        expect(table.table_exists?).to be_truthy
        expect(table.count).to eq(1)
      end

      def migration(command)
        version = migrations.size + 1
        file = "test_#{version}.sql"
        name = file.split('.').first
        allow(File).to receive(:read).with(file).and_return(command)
        migrations << base::CommandMigration.new(file, version, 'create', 'type', name, 1)
      end
    end
  end

  context 'on schema dumper' do
    let(:source) { ActiveRecord::Base.connection_pool }
    let(:schema_table) { double(commands_table.name) }
    let(:commands_table) { Torque::PostgreSQL::VersionedCommands::SchemaTable }
    let(:dump_result) do
      ActiveRecord::SchemaDumper.dump(source, (dump_result = StringIO.new))
      dump_result.string
    end

    before do
      allow(commands_table).to receive(:new).and_return(schema_table)
      allow(schema_table).to receive(:versions_of).and_return([])
      allow(schema_table).to receive(:table_name).and_return('versioned_commands_tbl')
    end

    it 'does not include versioned commands info by default' do
      expect(dump_result).not_to include('"versioned_commands_tbl"')
      expect(dump_result).not_to include('# These are types managed by versioned commands')
      expect(dump_result).not_to include('# These are functions managed by versioned commands')
      expect(dump_result).not_to include('# These are views managed by versioned commands')
    end

    it 'includes all types' do
      connection.execute('CREATE TYPE test;')
      connection.execute('CREATE TYPE internal.other;')

      allow(schema_table).to receive(:versions_of).with('type').and_return([
        ['test', 1],
        ['internal_other', 2],
        ['remove', 1],
      ])

      expect(dump_result).to include('# These are types managed by versioned commands')
      expect(dump_result).to include('create_type "test", version: 1')
      expect(dump_result).to include('create_type "internal_other", version: 2')
      expect(dump_result).not_to include('create_type "removed", version: 1')
    end

    it 'includes all functions' do
      body = 'RETURNS void AS $$ BEGIN NULL; END; $$ LANGUAGE plpgsql'
      connection.execute("CREATE FUNCTION test() #{body};")
      connection.execute("CREATE FUNCTION internal.other() #{body};")

      allow(schema_table).to receive(:versions_of).with('function').and_return([
        ['test', 1],
        ['internal_other', 2],
        ['remove', 1],
      ])

      expect(dump_result).to include('# These are functions managed by versioned commands')
      expect(dump_result).to include('create_function "test", version: 1')
      expect(dump_result).to include('create_function "internal_other", version: 2')
      expect(dump_result).not_to include('create_function "removed", version: 1')
    end

    it 'includes all views' do
      connection.execute('CREATE VIEW test AS SELECT 1;')
      connection.execute('CREATE MATERIALIZED VIEW internal.other AS SELECT 2;')

      allow(schema_table).to receive(:versions_of).with('view').and_return([
        ['test', 1],
        ['internal_other', 2],
        ['remove', 1],
      ])

      expect(dump_result).to include('# These are views managed by versioned commands')
      expect(dump_result).to include('create_view "test", version: 1')
      expect(dump_result).to include('create_view "internal_other", version: 2')
      expect(dump_result).not_to include('create_view "removed", version: 1')
    end
  end
end
