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
    # 'homepage_uri'    => 'https://torque.carlosfsilva.com/postgresql',
    "source_code_uri" => 'https://github.com/crashtech/torque-postgresql',
    'bug_tracker_uri' => 'https://github.com/crashtech/torque-postgresql/issues',
    # 'changelog_uri'   => 'https://github.com/crashtech/torque-postgresql/blob/master/CHANGELOG.md',
  }

  s.require_paths = ['lib']

  s.files        = Dir['MIT-LICENSE', 'README.rdoc', 'lib/**/*', 'Rakefile']
  s.test_files   = Dir['spec/**/*']
  s.rdoc_options = ['--title', 'Torque PostgreSQL']

  s.required_ruby_version     = '>= 2.7.2'
  s.required_rubygems_version = '>= 1.8.11'

  s.add_dependency 'rails', '>= 7.0'
  s.add_dependency 'pg', '>= 1.2'

  s.add_development_dependency 'rake', '~> 12.3', '>= 12.3.3'
  s.add_development_dependency 'database_cleaner', '~> 1.5', '>= 1.5.3'
  s.add_development_dependency 'dotenv', '~> 2.1', '>= 2.1.1'
  s.add_development_dependency 'rspec', '~> 3.5', '>= 3.5.0'

  s.add_development_dependency 'factory_bot', '~> 6.2', '>= 6.2.1'
  s.add_development_dependency 'faker', '~> 2.20'
end
