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

        # A cross join only ever carries its source
        def visit_Torque_PostgreSQL_Arel_Nodes_CrossJoin(o, collector)
          collector << 'CROSS JOIN '
          visit(o.left, collector)
        end

        # Every part here is written only when it is actually needed, since
        # LATERAL is a noise word on functions and ROWS FROM is only forced
        # by the counter
        def visit_Torque_PostgreSQL_Arel_Nodes_FromItem(o, collector)
          collector << 'LATERAL ' if o.lateral

          collector << 'ROWS FROM (' if o.rows_from?
          visit(o.left, collector)
          collector = visit_definitions(o.definitions, collector) << ')' if o.rows_from?

          collector << ' WITH ORDINALITY' if o.ordinality.present?
          collector << ' ' << quote_table_name(o.name)

          columns = o.alias_columns
          return collector if columns.blank?

          collector << '('
          visit_alias_columns(columns, collector)
          collector << ')'
        end

        # Allow casting any node
        def visit_Torque_PostgreSQL_Arel_Nodes_Cast(o, collector)
          visit(o.left, collector) << '::' << o.right
        end

        private

          # The column definition list a function has to be told to return
          def visit_definitions(definitions, collector)
            collector << ' AS ('
            visit_alias_columns(definitions, collector)
            collector << ')'
          end

          # A name on its own when it has no type, otherwise the name and the
          # type it is being given
          def visit_alias_columns(columns, collector)
            columns.each_with_index do |(name, type), index|
              collector << ', ' unless index.zero?
              collector << quote_column_name(name)
              collector << ' ' << type if type.present?
            end

            collector
          end

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
