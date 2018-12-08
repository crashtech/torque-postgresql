module Torque
  module PostgreSQL
    module Attributes
      module TypeMap

        class << self

          # Reader of the list of tyes
          def types
            @types ||= {}
          end

          # Store which elements should be initialized
          def decorable
            @decorable ||= Hash.new{ |h, k| h[k] = [] }
          end

          # List of options for each individual attribute on each klass
          def options
            @options ||= Hash.new{ |h, k| h[k] = {} }
          end

          # Mark the list of attributes on the given class that can be decorated
          def decorate(klass, *attributes, **set_options)
            attributes.flatten.each do |attribute|
              decorable[klass] << attribute.to_s
              options[klass][attribute.to_s] = set_options.deep_dup
            end
          end

          # Force the list of attributes on the given class to be decorated by
          # this type mapper
          def decorate!(klass, *attributes, **options)
            decorate(klass, *attributes, **options)
            attributes.flatten.map do |attribute|
              type = klass.attribute_types[attribute.to_s]
              lookup(type, klass, attribute.to_s)
            end
          end

          # Register a type that can be processed by a given block
          def register_type(key, &block)
            raise_type_defined(key) if present?(key)
            types[key] = block
          end

          # Search for a type match and process it if any
          def lookup(key, klass, attribute, *args)
            return unless present?(key) && decorable?(key, klass, attribute)

            set_options = options[klass][attribute]
            args.unshift(set_options) unless set_options.nil?
            klass.instance_exec(key, attribute, *args, &types[key.class])
          rescue LocalJumpError
            # There's a bug or misbehavior that blocks being called through
            # instance_exec don't accept neither return nor break
            return false
          end

          # Check if the given type class is registered
          def present?(key)
            types.key?(key.class)
          end

          # Check whether the given attribute on the given klass is
          # decorable by this type mapper
          def decorable?(key, klass, attribute)
            key.class.auto_initialize? ||
              (decorable.key?(klass) && decorable[klass].include?(attribute.to_s))
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
