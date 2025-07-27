require_relative '../lib/torque/postgresql/auxiliary_statement'

require_relative '../lib/torque/postgresql/adapter/schema_overrides'

require_relative '../lib/torque/postgresql/adapter/oid/box'
require_relative '../lib/torque/postgresql/adapter/oid/circle'
require_relative '../lib/torque/postgresql/adapter/oid/enum'
require_relative '../lib/torque/postgresql/adapter/oid/enum_set'
require_relative '../lib/torque/postgresql/adapter/oid/interval'
require_relative '../lib/torque/postgresql/adapter/oid/line'
require_relative '../lib/torque/postgresql/adapter/oid/segment'

require_relative '../lib/torque/postgresql/attributes/enum'
require_relative '../lib/torque/postgresql/attributes/enum_set'
require_relative '../lib/torque/postgresql/attributes/period'
require_relative '../lib/torque/postgresql/attributes/full_text_search'

require_relative '../lib/torque/postgresql/relation/auxiliary_statement'

module Torque
  module PostgreSQL
    ActiveRecord::Base.belongs_to_many_required_by_default = false

    Attributes::Enum.include_on(ActiveRecord::Base)
    Attributes::EnumSet.include_on(ActiveRecord::Base)
    Attributes::Period.include_on(ActiveRecord::Base)
    Attributes::FullTextSearch.include_on(ActiveRecord::Base)

    Relation.include(Relation::AuxiliaryStatement)

    ::Object.const_set('TorqueCTE', AuxiliaryStatement)
    ::Object.const_set('TorqueRecursiveCTE', AuxiliaryStatement::Recursive)

    config.enum.namespace = ::Object.const_set('Enum', Module.new)
    config.enum.namespace.define_singleton_method(:const_missing) do |name|
      Attributes::Enum.lookup(name)
    end

    config.enum.namespace.define_singleton_method(:sample) do |name|
      Attributes::Enum.lookup(name).sample
    end

    ar_type = ActiveRecord::Type
    ar_type.register(:enum,     Adapter::OID::Enum,     adapter: :postgresql)
    ar_type.register(:enum_set, Adapter::OID::EnumSet,  adapter: :postgresql)

    ar_type.register(:box,      Adapter::OID::Box,      adapter: :postgresql)
    ar_type.register(:circle,   Adapter::OID::Circle,   adapter: :postgresql)
    ar_type.register(:line,     Adapter::OID::Line,     adapter: :postgresql)
    ar_type.register(:segment,  Adapter::OID::Segment,  adapter: :postgresql)

    ar_type.register(:interval, Adapter::OID::Interval, adapter: :postgresql)

    Arel.build_operations(config.arel.infix_operators)

    drop_file = Pathname.new(__dir__).join('../lib/torque/postgresql/versioned_commands/drop_any_view.sql')
    VersionedCommands.register(:views, drop_with: File.read(drop_file)) if defined?(VersionedCommands)

    drop_file = Pathname.new(__dir__).join('../lib/torque/postgresql/versioned_commands/drop_any_function.sql')
    VersionedCommands.register(:functions, drop_with: File.read(drop_file)) if defined?(VersionedCommands)

    ActiveRecord::Base.connection.torque_load_additional_types
  end
end
