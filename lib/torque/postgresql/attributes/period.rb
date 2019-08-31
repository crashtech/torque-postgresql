module Torque
  module PostgreSQL
    module Attributes
      # For naw, period doesn't have it's own class
      module Period
        class << self
          # Provide a method on the given class to setup which period columns
          # will be manually initialized
          def include_on(klass, method_name = nil)
            method_name ||= Torque::PostgreSQL.config.period.base_method
            Builder.include_on(klass, method_name, Builder::Period)
          end
        end
      end
    end
  end
end
