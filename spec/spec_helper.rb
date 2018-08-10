require 'torque-postgresql'
require 'database_cleaner'
require 'factory_girl'
require 'dotenv'
require 'faker'
require 'rspec'
require 'byebug'

Dotenv.load

ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])
Dir.glob(File.join('spec', '{models,factories,mocks}', '**', '*.rb')) do |file|
  require file[5..-4]
end

I18n.load_path << Pathname.pwd.join('spec', 'en.yml')

load File.join('schema.rb')
RSpec.configure do |config|
  config.extend Mocks::CreateTable

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

end
