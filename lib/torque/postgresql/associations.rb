require_relative 'associations/association_scope'
require_relative 'associations/belongs_to_many_association'
require_relative 'associations/foreign_association'

require_relative 'associations/builder'
require_relative 'associations/preloader'

association_mod = Torque::PostgreSQL::Associations::ForeignAssociation
::ActiveRecord::Associations::HasManyAssociation.prepend(association_mod)
::ActiveRecord::Associations::BelongsToManyAssociation.prepend(association_mod)
