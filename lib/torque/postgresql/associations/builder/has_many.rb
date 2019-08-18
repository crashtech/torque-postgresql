module Torque
  module PostgreSQL
    module Associations
      module Builder
        module HasMany
          def valid_options(options)
            super + [:array]
          end
        end

        ::ActiveRecord::Associations::Builder::HasMany.extend(HasMany)
      end
    end
  end
end
