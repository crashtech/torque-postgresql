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
            klass.define_singleton_method(method_name) do |*args, **options|
              args.each do |attribute|
                builder = Builder::Period.new(self, attribute, options)
                builder.conflicting?
                builder.build
              end
            end
          end
        end
      end
    end
  end
end
