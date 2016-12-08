begin
  require 'bundler/setup'
rescue LoadError
  puts 'You must `gem install bundler` and `bundle install` to run rake tasks'
end

require 'rdoc/task'

RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'Torque::Postgresql'
  rdoc.options << '--line-numbers'
  rdoc.rdoc_files.include('README.rdoc')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

desc 'Prints a schema dump of the test database'
task :dump do |t|
  lib  = File.expand_path('../lib', __FILE__)
  spec = File.expand_path('../spec', __FILE__)
  $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
  $LOAD_PATH.unshift(spec) unless $LOAD_PATH.include?(spec)

  require 'byebug'
  require 'spec_helper'
  ActiveRecord::SchemaDumper.dump
end

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)
task default: :spec
