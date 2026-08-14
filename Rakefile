begin
  require 'bundler/setup'
rescue LoadError
  puts 'You must `gem install bundler` and `bundle install` to run rake tasks'
end

require 'bundler/gem_tasks'
require 'rdoc/task'

DOCS_PATH = File.expand_path('docs', __dir__)

desc 'Compile the documentation site into docs/_site'
task :docs do
  version = File.read(File.expand_path('lib/torque/postgresql/version.rb', __dir__))[/VERSION = '([^']+)'/, 1]
  published = File.read(File.join(DOCS_PATH, '_config.yml'))[/^gem_version:\s*(\S+)/, 1]

  unless published == version
    abort <<~MESSAGE
      docs/_config.yml says gem_version: #{published}, but the gem is #{version}.
      The site prints that number in its header, so update _config.yml before building.
    MESSAGE
  end

  env = { 'BUNDLE_GEMFILE' => File.join(DOCS_PATH, 'Gemfile') }
  Dir.chdir(DOCS_PATH) { sh(env, 'bundle', 'exec', 'jekyll', 'build') }
end

# A gem cut from master carries freshly compiled docs; every other branch skips
# the cost. Publishing docs/_site stays a manual step.
branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
Rake::Task[:build].enhance([:docs]) if branch == 'master'

RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'Torque::Postgresql'
  rdoc.options << '--line-numbers'
  rdoc.rdoc_files.include('README.rdoc')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

desc 'Initialize the local environment'
task :environment do |t|
  lib  = File.expand_path('../lib', __FILE__)
  spec = File.expand_path('../spec', __FILE__)
  $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
  $LOAD_PATH.unshift(spec) unless $LOAD_PATH.include?(spec)
end

desc 'Prints a schema dump of the test database'
task dump: :environment do |t|
  require 'byebug'
  require 'spec_helper'
  ActiveRecord::SchemaDumper.dump
end

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)
task default: :spec
