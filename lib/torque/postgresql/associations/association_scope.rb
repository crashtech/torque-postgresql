module Torque
  module PostgreSQL
    module Associations
      module AssociationScope

        module ClassMethods
          def get_bind_values(*)
            super.flatten
          end
        end

        private

          # When the relation is connected through an array, intercept the
          # condition builder and uses an overlap condition building it on
          # +build_id_constraint+
          def last_chain_scope(scope, *args)
            # 5.0 table, reflection, owner, association_klass
            # 5.1 table, reflection, owner
            # 5.2 reflection, owner

            reflection = args.size.eql?(2) ? args[0] : args[1]
            return super unless reflection.connected_through_array?

            table = args[0] if args.size > 2
            keys = args.size.eql?(4) ? reflection.join_keys(args[3]) : reflection.join_keys
            owner = args.size.eql?(2) ? args[1] : args[2]

            value = transform_value(owner[keys.foreign_key])
            constraint, binds = build_id_constraint(reflection, keys, value, table, true)

            if Torque::PostgreSQL::AR521
              scope.where!(constraint)
            else
              klass = ::ActiveRecord::Relation::WhereClause
              scope.where_clause += klass.new([constraint], binds)
              scope
            end
          end

          # When the relation is connected through an array, intercept the
          # condition builder and uses an overlap condition building it on
          # +build_id_constraint+
          def next_chain_scope(scope, *args)
            # 5.0 table, reflection, association_klass, foreign_table, next_reflection
            # 5.1 table, reflection, foreign_table, next_reflection
            # 5.2 reflection, next_reflection

            reflection = args.size.eql?(2) ? args[0] : args[1]
            return super unless reflection.connected_through_array?

            table = args[0] if args.size > 2
            next_reflection = args[-1]

            foreign_table = args[-2] if args.size.eql?(5)
            foreign_table ||= next_reflection.aliased_table

            keys = args.size.eql?(5) ? reflection.join_keys(args[2]) : reflection.join_keys

            value = foreign_table[keys.foreign_key]
            constraint, *_ = build_id_constraint(reflection, keys, value, table)

            scope.joins!(join(foreign_table, constraint))
          end

          # Trigger the same method on the relation which will build the
          # constraint condition using array logics
          def build_id_constraint(reflection, keys, value, table = nil, bind_param = false)
            table ||= reflection.aliased_table
            value, binds = build_binds_for_constraint(reflection, value, keys.foreign_key) \
              if bind_param

            [reflection.build_id_constraint(table[keys.key], value), binds]
          end

          # For array-like values, it needs to call the method as many times as
          # the array size
          def transform_value(value)
            if value.is_a?(::Enumerable)
              value.map { |v| value_transformation.call(v) }
            else
              value_transformation.call(value)
            end
          end

          # When binds are necessary for a constraint, instantiate them
          if Torque::PostgreSQL::AR521
            def build_binds_for_constraint(reflection, values, foreign_key)
              result = Array.wrap(values).map do |value|
                ::Arel::Nodes::BindParam.new(::ActiveRecord::Relation::QueryAttribute.new(
                  foreign_key, value, reflection.klass.attribute_types[foreign_key],
                ))
              end

              [result, nil]
            end
          else
            def build_binds_for_constraint(reflection, values, foreign_key)
              type = reflection.klass.attribute_types[foreign_key]
              parts = Array.wrap(values).map do |value|
                bind = ::Arel::Nodes::BindParam.new
                value = ::ActiveRecord::Relation::QueryAttribute.new(foreign_key, value, type)
                [bind, value]
              end.to_h

              [parts.keys, parts.values]
            end
          end

      end

      ::ActiveRecord::Associations::AssociationScope.singleton_class.prepend(AssociationScope::ClassMethods)
      ::ActiveRecord::Associations::AssociationScope.prepend(AssociationScope)
    end
  end
end
