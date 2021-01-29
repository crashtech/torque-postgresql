# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Reflection
      module AbstractReflection
        AREL_ATTR = ::Arel::Attributes::Attribute

        ARR_NO_CAST = 'bigint'
        ARR_CAST = 'bigint[]'

        # Check if the foreign key actually exists
        def connected_through_array?
          false
        end

        # Fix where the join_scope method is the one now responsible for
        # building the join condition
        def join_scope(table, foreign_table, foreign_klass)
          return super unless connected_through_array?

          predicate_builder = predicate_builder(table)
          scope_chain_items = join_scopes(table, predicate_builder)
          klass_scope       = klass_join_scope(table, predicate_builder)

          klass_scope.where!(build_id_constraint_between(table, foreign_table))
          klass_scope.where!(type => foreign_klass.polymorphic_name) if type
          klass_scope.where!(klass.send(:type_condition, table)) \
            if klass.finder_needs_type_condition?

          scope_chain_items.inject(klass_scope, &:merge!)
        end

        # Manually build the join constraint
        def build_join_constraint(table, foreign_table)
          result = build_id_constraint_between(table, foreign_table)
          result = table.create_and([result, klass.send(:type_condition, table)]) \
            if klass.finder_needs_type_condition?

          result
        end

        # Build the id constraint checking if both types are perfect matching
        def build_id_constraint(klass_attr, source_attr)
          return klass_attr.eq(source_attr) unless connected_through_array?

          # Klass and key are associated with the reflection Class
          klass_type = klass.columns_hash[join_keys.key.to_s]
          # active_record and foreign_key are associated with the source Class
          source_type = active_record.columns_hash[join_keys.foreign_key.to_s]

          # If both are attributes but the left side is not an array, and the
          # right side is, use the ANY operation
          any_operation = arel_array_to_any(klass_attr, source_attr, klass_type, source_type)
          return klass_attr.eq(any_operation) if any_operation

          # If the left side is not an array, just use the IN condition
          return klass_attr.in(source_attr) unless klass_type.try(:array)

          # Decide if should apply a cast to ensure same type comparision
          should_cast = klass_type.type.eql?(:integer) && source_type.type.eql?(:integer)
          should_cast &= !klass_type.sql_type.eql?(source_type.sql_type)
          should_cast |= !(klass_attr.is_a?(AREL_ATTR) && source_attr.is_a?(AREL_ATTR))

          # Apply necessary transformations to values
          klass_attr = cast_constraint_to_array(klass_type, klass_attr, should_cast)
          source_attr = cast_constraint_to_array(source_type, source_attr, should_cast)

          # Return the overlap condition
          klass_attr.overlaps(source_attr)
        end

        if PostgreSQL::AR610
          # TODO: Deprecate this method
          def join_keys
            OpenStruct.new(key: join_primary_key, foreign_key: join_foreign_key)
          end
        end

        private

          def build_id_constraint_between(table, foreign_table)
            klass_attr  = table[join_primary_key]
            source_attr = foreign_table[join_foreign_key]

            build_id_constraint(klass_attr, source_attr)
          end

          # Prepare a value for an array constraint overlap condition
          def cast_constraint_to_array(type, value, should_cast)
            base_ready = type.try(:array) && value.is_a?(AREL_ATTR)
            return value if base_ready && (type.sql_type.eql?(ARR_NO_CAST) || !should_cast)

            value = ::Arel::Nodes.build_quoted(Array.wrap(value)) unless base_ready
            value = value.cast(ARR_CAST) if should_cast
            value
          end

          # Check if it's possible to turn both attributes into an ANY condition
          def arel_array_to_any(klass_attr, source_attr, klass_type, source_type)
            return unless !klass_type.try(:array) && source_type.try(:array) &&
              klass_attr.is_a?(AREL_ATTR) && source_attr.is_a?(AREL_ATTR)

            ::Arel::Nodes::NamedFunction.new('ANY', [source_attr])
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

      ::ActiveRecord::Reflection::AbstractReflection.prepend(AbstractReflection)
    end
  end
end
