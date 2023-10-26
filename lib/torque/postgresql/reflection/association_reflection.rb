# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Reflection
      module AssociationReflection

        def initialize(name, scope, options, active_record)
          super

          raise ArgumentError, <<-MSG.squish if options[:array] && options[:polymorphic]
            Associations can't be connected through an array at the same time they are
            polymorphic. Please choose one of the options.
          MSG
        end

        private

          # Check if the foreign key should be pluralized
          def derive_foreign_key(*)
            result = super
            result = ActiveSupport::Inflector.pluralize(result) \
              if collection? && connected_through_array?
            result
          end

          # returns either +nil+ or the inverse association name that it finds.
          def automatic_inverse_of
            return super unless connected_through_array?

            if can_find_inverse_of_automatically?(self)
              inverse_name = options[:as] || active_record.name.demodulize
              inverse_name = ActiveSupport::Inflector.underscore(inverse_name)
              inverse_name = ActiveSupport::Inflector.pluralize(inverse_name)
              inverse_name = inverse_name.to_sym

              begin
                reflection = klass._reflect_on_association(inverse_name)
              rescue NameError
                # Give up: we couldn't compute the klass type so we won't be able
                # to find any associations either.
                reflection = false
              end

              return inverse_name if valid_inverse_reflection?(reflection)
            end
          end

      end

      ::ActiveRecord::Reflection::AssociationReflection.prepend(AssociationReflection)
    end
  end
end
