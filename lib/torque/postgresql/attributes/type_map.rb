module Torque
  module PostgreSQL
    module Attributes
      module TypeMap

        class << self

          def types
            @types ||= {}
          end

          def register_type(key, &block)
            raise_type_defined(key) if present?(key)
            types[key] = block
          end

          def lookup(key, *args)
            return unless present?(key)
            types[key.class].(key, *args)
          end

          def present?(key)
            types.key?(key.class)
          end

          def raise_type_defined(key)
            raise ArgumentError, <<-MSG.strip
              Type #{key} is already defined here: #{types[key].source_location.join(':')}
            MSG
          end

        end

      end
    end
  end
end
