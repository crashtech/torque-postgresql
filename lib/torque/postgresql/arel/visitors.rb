module Torque
  module PostgreSQL
    module Arel
      module Visitors
        def visit_Arel_SelectManager o, collector
          collector << '('
          visit(o.ast, collector) << ')'
        end
      end

      ::Arel::Visitors::ToSql.prepend Visitors
    end
  end
end
