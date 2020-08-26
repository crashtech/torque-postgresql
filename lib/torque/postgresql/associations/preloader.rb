require_relative 'preloader/association'

unless Torque::PostgreSQL::AR521
  module Torque
    module PostgreSQL
      module Associations
        module Preloader
          class BelongsToMany < ::ActiveRecord::Associations::Preloader::HasMany
            def association_key_name
              reflection.active_record_primary_key
            end

            def owner_key_name
              reflection.foreign_key
            end
          end

          def preloader_for(reflection, owners, *)
            return AlreadyLoaded \
              if owners.first.association(reflection.name).loaded?

            return BelongsToMany \
              if reflection.macro.eql?(:belongs_to_many)

            super
          end
        end

        ::ActiveRecord::Associations::Preloader.prepend(Preloader)
      end
    end
  end
end
