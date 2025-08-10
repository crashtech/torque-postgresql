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

        # Allow quoted arrays to get here
        def visit_Arel_Nodes_Casted(o, collector)
          value = o.value_for_database
          klass = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array::Data
          return super unless value.is_a?(klass)
          quote_array(value.values, collector)
        end

        ## TORQUE VISITORS
        def visit_Torque_PostgreSQL_Arel_Nodes_Ref(o, collector)
          collector << quote_table_name(o.expr)
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
