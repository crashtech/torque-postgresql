$:.push File.expand_path('../lib', __FILE__)

# Maintain your gem's version:
require 'torque/postgresql/version'
require 'date'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'torque-postgresql'
  s.version     = Torque::PostgreSQL::VERSION
  s.date        = Date.today.to_s
  s.authors     = ['Carlos Silva']
  s.email       = ['me@carlosfsilva.com']
  s.homepage    = 'https://github.com/crashtech/torque-postgresql'
  s.summary     = 'ActiveRecord extension to access PostgreSQL advanced resources'
  s.description = 'Add support to complex resources of PostgreSQL, like data types, array associations, and auxiliary statements (CTE)'
  s.license     = 'MIT'
  s.metadata    = {
    'homepage_uri'    => 'https://torque.dev/postgresql',
    "source_code_uri" => 'https://github.com/crashtech/torque-postgresql',
    'bug_tracker_uri' => 'https://github.com/crashtech/torque-postgresql/issues',
    'changelog_uri'   => 'https://github.com/crashtech/torque-postgresql/releases',
  }

  s.require_paths = ['lib']

  s.files        = Dir['MIT-LICENSE', 'README.rdoc', 'lib/**/*', 'Rakefile']
  s.test_files   = Dir['spec/**/*']
  s.rdoc_options = ['--title', 'Torque PostgreSQL']

  s.required_ruby_version     = '>= 3.2'
  s.required_rubygems_version = '>= 1.8.11'

  s.add_dependency 'rails', '~> 8.0'
  s.add_dependency 'pg', '>= 1.2'

  s.add_development_dependency 'rake', '~> 13.0'
  s.add_development_dependency 'database_cleaner', '~> 2.0'
  s.add_development_dependency 'dotenv', '~> 3.1'
  s.add_development_dependency 'rspec', '~> 3.5'

  s.add_development_dependency 'factory_bot', '~> 6.2'
  s.add_development_dependency 'faker', '~> 3.5'
end
