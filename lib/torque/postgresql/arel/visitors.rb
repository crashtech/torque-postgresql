# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Arel
      module Visitors
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

        ## TORQUE VISITORS
        def visit_Torque_PostgreSQL_Arel_Nodes_Ref(o, collector)
          collector << quote_table_name(o.expr)
        end

        # Access a single column of a composite value
        def visit_Torque_PostgreSQL_Arel_Nodes_Column(o, collector)
          collector << '('
          visit(o.left, collector)
          collector << ').' << quote_column_name(o.right)
        end

        # Access a single property of a document, as text, so that it can then
        # be casted to whatever the property is supposed to be
        def visit_Torque_PostgreSQL_Arel_Nodes_Property(o, collector)
          collector << '('
          visit(o.left, collector)
          collector << ' #>> '
          visit(::Arel.array(o.path), collector)
          collector << ')'
          collector << '::' << o.cast if o.cast
          collector
        end

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
