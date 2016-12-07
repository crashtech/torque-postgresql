require 'torque-postgresql'
require 'database_cleaner'
require 'dotenv'

Dotenv.load

ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])
Dir.glob(File.join('{models,factories}', '*.rb'), &method(:require))

load File.join('schema.rb')
RSpec.configure do |config|
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
