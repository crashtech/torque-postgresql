module Torque
  module PostgreSQL
    module Attributes
      module TypeMap

        class << self

          # Reader of the list of tyes
          def types
            @types ||= {}
          end

          # Register a type that can be processed by a given block
          def register_type(key, &block)
            raise_type_defined(key) if present?(key)
            types[key] = block
          end

          # Search for a type match and process it if any
          def lookup(key, klass, *args)
            return unless present?(key)
            klass.instance_exec(key, *args, &types[key.class])
          rescue LocalJumpError
            # There's a bug or misbehavior that blocks being called through
            # instance_exec don't accept neither return nor break
            return false
          end

          # Check if the given type class is registered
          def present?(key)
            types.key?(key.class)
          end

          # Message when trying to define multiple types
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
