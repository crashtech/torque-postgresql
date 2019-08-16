module Torque
  module PostgreSQL
    module Reflection
      module AbstractReflection
        AREL_ATTR = ::Arel::Attributes::Attribute

        ARR_NO_CAST = 'bigint'.freeze
        ARR_CAST = 'bigint[]'.freeze

        # Check if the foreign key actually exists
        def connected_through_array?
          false
        end

        # Manually build the join constraint
        def build_join_constraint(table, foreign_table)
          join = method(:join_keys).arity.eql?(0) ? join_keys : join_keys(klass)

          klass_attr = table[join.key]
          source_attr = foreign_table[join.foreign_key]

          result = build_id_constraint(klass_attr, source_attr)
          result = table.create_and([result, klass.send(:type_condition, table)]) \
            if klass.finder_needs_type_condition?

          result
        end

        # Build the id constraint checking if both types are perfect matching
        # TODO: Try to simplify by `tags.id = ANY(videos.tag_ids)`
        def build_id_constraint(klass_attr, source_attr)
          return klass_attr.eq(source_attr) unless connected_through_array?
          join = method(:join_keys).arity.eql?(0) ? join_keys : join_keys(klass)

          # Klass and key are associated with the reflection Class
          klass_type = klass.columns_hash[join.key]
          # active_record and foreign_key are associated with the source Class
          source_type = active_record.columns_hash[join.foreign_key]

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

        private

          # Prepare a value for an array constraint overlap condition
          def cast_constraint_to_array(type, value, should_cast)
            base_ready = type.try(:array) && value.is_a?(AREL_ATTR)
            return value if base_ready && (type.sql_type.eql?(ARR_NO_CAST) || !should_cast)

            value = ::Arel::Nodes.build_quoted(Array.wrap(value)) unless base_ready
            value = value.cast(ARR_CAST) if should_cast
            value
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
