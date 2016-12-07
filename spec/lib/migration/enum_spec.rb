require 'spec_helper'

RSpec.describe 'Enum', 'on migration' do
  before(:each) { ActiveRecord::Base.connection.drop_type(:status) }

  let(:migration) { ActiveRecord::Base.connection }

  it 'can be created' do
    migration.create_enum(:status, %i(foo bar))
    expect(migration.type_exists?(:status)).to be_truthy
    expect(migration.enum_values(:status)).to eql(['foo', 'bar'])
  end

  it 'can be deleted' do
    migration.create_enum(:status, %i(foo bar))
    expect(migration.type_exists?(:status)).to be_truthy

    migration.drop_type(:status)
    expect(migration.type_exists?(:status)).to be_falsey
  end

  it 'can be renamed' do
    migration.create_enum(:status, %i(foo bar))
    migration.rename_type(:status, :new_status)
    expect(migration.type_exists?(:new_status)).to be_truthy
    expect(migration.type_exists?(:status)).to be_falsey
  end

  it 'can have prefix' do
    migration.create_enum(:status, %i(foo bar), prefix: true)
    expect(migration.enum_values(:status)).to eql(['status_foo', 'status_bar'])
  end

  it 'can have suffix' do
    migration.create_enum(:status, %i(foo bar), suffix: 'tst')
    expect(migration.enum_values(:status)).to eql(['foo_tst', 'bar_tst'])
  end

  it 'inserts values at the end' do
    migration.create_enum(:status, %i(foo bar))
    migration.add_enum_values(:status, %i(baz qux))
    expect(migration.enum_values(:status)).to eql(['foo', 'bar', 'baz', 'qux'])
  end

  it 'inserts values in the beginning' do
    migration.create_enum(:status, %i(foo bar))
    migration.add_enum_values(:status, %i(baz qux), prepend: true)
    expect(migration.enum_values(:status)).to eql(['baz', 'qux', 'foo', 'bar'])
  end

  it 'inserts values in the middle' do
    migration.create_enum(:status, %i(foo bar))
    migration.add_enum_values(:status, %i(baz), after: 'foo')
    expect(migration.enum_values(:status)).to eql(['foo', 'baz', 'bar'])

    migration.add_enum_values(:status, %i(qux), before: 'bar')
    expect(migration.enum_values(:status)).to eql(['foo', 'baz', 'qux', 'bar'])
  end

  it 'inserts values with prefix or suffix' do
    migration.create_enum(:status, %i(foo bar))
    migration.add_enum_values(:status, %i(baz), prefix: true)
    migration.add_enum_values(:status, %i(qux), suffix: 'tst')
    expect(migration.enum_values(:status)).to eql(['foo', 'bar', 'status_baz', 'qux_tst'])

  end
end
