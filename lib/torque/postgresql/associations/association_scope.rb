module Torque
  module PostgreSQL
    module Associations
      module AssociationScope

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
            constraint = build_id_constraint(reflection, keys, value, table)

            scope.where!(constraint)
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
            constraint = build_id_constraint(reflection, keys, value, table)

            scope.joins!(join(foreign_table, constraint))
          end

          # Trigger the same method on the relation which will build the
          # constraint condition using array logics
          def build_id_constraint(reflection, join_keys, value, table = nil)
            table ||= reflection.aliased_table
            reflection.build_id_constraint(table[join_keys.key], value)
          end

      end

      ::ActiveRecord::Associations::AssociationScope.prepend(AssociationScope)
    end
  end
end
