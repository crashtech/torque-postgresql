require 'torque-postgresql'
require 'database_cleaner'
require 'factory_bot'
require 'dotenv'
require 'faker'
require 'rspec'
require 'byebug'

Dotenv.load

ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])
cache = ActiveRecord::Base.connection.schema_cache

cleaner = ->() do
  cache.instance_variable_set(:@inheritance_loaded, false)
  cache.instance_variable_set(:@inheritance_dependencies, {})
  cache.instance_variable_set(:@inheritance_associations, {})
end

load File.join('schema.rb')
Dir.glob(File.join('spec', '{models,factories,mocks}', '*.rb')) do |file|
  require file[5..-4]
end

cleaner.call
I18n.load_path << Pathname.pwd.join('spec', 'en.yml')
RSpec.configure do |config|
  config.extend Mocks::CreateTable
  config.include Mocks::CacheQuery

  config.formatter = :documentation
  config.color     = true
  config.tty       = true

  # Handles acton before rspec initialize
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end

  config.before(:each, js: true) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end

  config.before(:each) do
    cleaner.call
  end
end
