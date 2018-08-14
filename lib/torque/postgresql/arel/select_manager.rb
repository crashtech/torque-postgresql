module Torque
  module PostgreSQL
    module Arel
      module SelectManager

        def using column
          column = ::Arel::Nodes::SqlLiteral.new(column.to_s)
          @ctx.source.right.last.right = Using.new(column)
          self
        end

        def only
          @ctx.source.only = true
        end

      end

      ::Arel::SelectManager.include SelectManager
    end
  end
end
