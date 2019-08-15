module Torque
  module PostgreSQL
    module Reflection
      module AbstractReflection

        # Check if the foreign key actually exists
        def connected_through_array?
          false
        end

        # Manually build the join constraint
        def build_join_constraint(table, foreign_table)
          join = method(:join_keys).arity.eql?(0) ? join_keys : join_keys(klass)

          klass_attr = table[join_keys.key]
          source_attr = foreign_table[join_keys.foreign_key]

          result = build_id_constraint(klass_attr, source_attr)
          result = table.create_and([result, klass.send(:type_condition, table)]) \
            if klass.finder_needs_type_condition?

          result
        end

        # Build the id constraint checking if both types are perfect matching
        def build_id_constraint(klass_attr, source_attr)
          return klass_attr.eq(source_attr) unless connected_through_array?
          join = method(:join_keys).arity.eql?(0) ? join_keys : join_keys(klass)

          # Klass and key are associated with the reflection Class
          klass_type = klass.columns_hash[join.key]
          # active_record and foreign_key are associated with the source Class
          source_type = active_record.columns_hash[join.foreign_key]

          # Check which types are array
          klass_array = klass_type.try(:array)
          source_array = source_type.try(:array)

          # If none of the types are an array, raise an error
          raise ArgumentError, <<-MSG.squish unless klass_array || source_array
            The association #{name} is marked as connected through an array but none of the
            attributes are an actual array. Please remove that option from the settings
            '#{macro}' :#{name}, array: false
          MSG

          # Decide if should apply a cast
          attr_klass = ::Arel::Attributes::Attribute
          should_cast = klass_type.type.eql?(:integer) && source_type.type.eql?(:integer)
          should_cast &= !klass_type.sql_type.eql?(source_type.sql_type)
          should_cast |= !(klass_attr.is_a?(attr_klass) && source_attr.is_a?(attr_klass))

          # Make sure that both attributes are set as quoted arrays
          klass_attr = ::Arel::Nodes.build_quoted(Array.wrap(klass_attr)) unless klass_array
          source_attr = ::Arel::Nodes.build_quoted(Array.wrap(source_attr)) unless source_array

          # Cast values if they are different but both are integer
          if should_cast
            klass_attr = klass_attr.cast('bigint[]')
            source_attr = source_attr.cast('bigint[]')
          end

          # Return the overlap condition
          klass_attr.overlap(source_attr)
        end

      end

      ::ActiveRecord::Reflection::AbstractReflection.prepend(AbstractReflection)
    end
  end
end
