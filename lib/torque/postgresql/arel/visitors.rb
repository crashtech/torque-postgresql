# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Arel
      module Visitors
        # Enclose select manager with parenthesis
        # :TODO: Remove when checking the new version of Arel
        def visit_Arel_SelectManager(o, collector)
          collector << '('
          visit(o.ast, collector) << ')'
        end

        # Add ONLY modifier to query
        def visit_Arel_Nodes_JoinSource(o, collector)
          collector << 'ONLY ' if o.only?
          super
        end

        # Allow quoted arrays to get here
        def visit_Arel_Nodes_Quoted(o, collector)
          return super unless o.expr.is_a?(::Enumerable)
          quote_array(o.expr, collector)
        end

        # Allow quoted arrays to get here
        def visit_Arel_Nodes_Casted(o, collector)
          value = o.value_for_database
          return super unless value.is_a?(::Enumerable)
          quote_array(value, collector)
        end

        ## TORQUE VISITORS
        # Allow casting any node
        def visit_Torque_PostgreSQL_Arel_Nodes_Cast(o, collector)
          visit(o.left, collector) << '::' << o.right
        end

        private

          def quote_array(value, collector)
            value = value.map(&::Arel::Nodes.method(:build_quoted))

            collector << 'ARRAY['
            visit_Array(value, collector)
            collector << ']'
          end
      end

      ::Arel::Visitors::PostgreSQL.prepend(Visitors)
    end
  end
end
