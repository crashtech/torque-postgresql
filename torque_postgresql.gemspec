$:.push File.expand_path('../lib', __FILE__)

# Maintain your gem's version:
require 'torque/postgresql/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'torque-postgresql'
  s.version     = Torque::PostgreSQL::VERSION
  s.authors     = ['Carlos Silva']
  s.email       = ['carlinhus.fsilva@gmail.com']
  s.homepage    = 'https://github.com/crashtech/torque-postgresql'
  s.summary     = 'ActiveRecord extension to access PostgreSQL advanced resources'
  s.description = 'Add support to complex resources of PostgreSQL, like data types, user-defined types and auxiliary statements (CTE)'
  s.license     = 'MIT'

  s.require_paths = ['lib']

  s.files      = Dir['MIT-LICENSE', 'README.rdoc', 'lib/**/*', 'Rakefile']
  s.test_files = Dir['test/**/*']

  s.required_ruby_version     = '>= 2.2.2'
  s.required_rubygems_version = '>= 1.8.11'

  s.add_dependency 'rails', '~> 5.0', '>= 5.0.0'
  s.add_dependency 'pg', '~> 0.19', '>= 0.19.0'

  s.add_development_dependency 'rake', '~> 10.1', '>= 10.1.0'
  s.add_development_dependency 'database_cleaner', '~> 1.5', '>= 1.5.3'
  s.add_development_dependency 'dotenv', '~> 2.1', '>= 2.1.1'
  s.add_development_dependency 'rspec', '~> 3.5', '>= 3.5.0'

  s.add_development_dependency 'factory_girl', '~> 4.5', '>= 4.5.0'
  s.add_development_dependency 'faker', '~> 1.5', '>= 1.5.0'
end
