require 'i18n'
require 'ostruct'
require 'active_model'
require 'active_record'
require 'active_support'

require 'active_support/core_ext/date/acts_like'
require 'active_support/core_ext/time/zones'
require 'active_record/connection_adapters/postgresql_adapter'

require 'torque/postgresql/config'
require 'torque/postgresql/version'
require 'torque/postgresql/collector'
require 'torque/postgresql/geometry_builder'
require 'torque/postgresql/predicate_builder'

require 'torque/postgresql/i18n'
require 'torque/postgresql/arel'
require 'torque/postgresql/adapter'
require 'torque/postgresql/associations'
require 'torque/postgresql/attributes'
require 'torque/postgresql/autosave_association'
require 'torque/postgresql/inheritance'
require 'torque/postgresql/base' # Needs to be after inheritance
require 'torque/postgresql/insert_all'
require 'torque/postgresql/migration'
require 'torque/postgresql/relation'
require 'torque/postgresql/reflection'
require 'torque/postgresql/schema_cache'
require 'torque/postgresql/table_name'
require 'torque/postgresql/function'

require 'torque/postgresql/railtie' if defined?(Rails)
