require 'i18n'
require 'active_model'
require 'active_record'
require 'active_support'

require 'active_support/core_ext/hash/compact'
require 'active_record/connection_adapters/postgresql_adapter'

require 'torque/postgresql/config'
require 'torque/postgresql/version'
require 'torque/postgresql/collector'

require 'torque/postgresql/i18n'
require 'torque/postgresql/adapter'
require 'torque/postgresql/attributes'
require 'torque/postgresql/auxiliary_statement'
require 'torque/postgresql/base'
require 'torque/postgresql/migration'
require 'torque/postgresql/relation'
require 'torque/postgresql/schema_dumper'

gdep = Gem::Dependency.new('arel', '~> 9.0.0')
unless gdep.matching_specs.sort_by(&:version).last
  require 'torque/postgresql/arel/visitors'
end
