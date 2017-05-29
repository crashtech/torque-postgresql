module Torque
  module PostgreSQL
    module Arel
      module Visitors
        # Enclose select manager with parenthesis
        def visit_Arel_SelectManager o, collector
          collector << '('
          visit(o.ast, collector) << ')'
        end

        # Add ONLY modifier to query
        def visit_Arel_Nodes_JoinSource(o, collector)
          collector << 'ONLY ' if o.only?
          super
        end
      end

      ::Arel::Visitors::PostgreSQL.include Visitors
    end
  end
end
