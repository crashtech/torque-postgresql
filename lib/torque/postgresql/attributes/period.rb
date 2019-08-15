module Torque
  module PostgreSQL
    module Attributes
      # For naw, period doesn't have it's own class
      module Period
        class << self

          # Provide a method on the given class to setup which period columns
          # will be manually initialized
          def include_on(klass)
            method_name = Torque::PostgreSQL.config.period.base_method
            klass.singleton_class.class_eval do
              define_method(method_name) do |*args, **options|
                Torque::PostgreSQL::Attributes::TypeMap.decorate(self, args, **options)
              end
            end
          end

        end
      end

      # Create the methods related to the attribute to handle the enum type
      TypeMap.register_type Adapter::OID::Range do |subtype, attribute, options = nil|
        # Generate methods on self class
        builder = Builder::Period.new(self, attribute, subtype, options || {})
        break if builder.conflicting?
        builder.build
      end
    end
  end
end
