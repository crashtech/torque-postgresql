module Torque
  module PostgreSQL
    class AuxiliaryStatement

      def initialize(table, klass)
        @table = Arel::Table.new(table)
        @attributes = {}
        @join_attributes = []
        @join_type = :inner
        @join_on = []
        @base = klass
        @query = nil
      end

      # Provides a map of attributes to be exposed to the main query.
      #
      # For instace, if the statement query has an 'id' column that you want
      # it to be accessed on the main query as 'item_id', you can use:
      #   attributes id: :item_id
      #
      # If its statement has more tables, and you want to expose those fields,
      # then:
      #   attributes 'table.name': :item_name
      def attributes(*list)
        @attributes = list.extract_options!
      end

      # Changes the type of the join and set the constraints
      #
      # The left side of the hash is the source table column, the right side is
      # the statement table column, now it's only accepting '=' constraints
      #   join id: :user_id
      #   join id: :'user.id'
      #   join 'post.id': :'user.last_post_id'
      #
      # It's possible to change the default type of join
      #   join :left, id: :user_id
      def join(*args)
        constraints = args.extract_options!
        base_table = @base.arel_table

        @join_attributes = constraints.values
        @join_type = args.fetch(0, @join_type)
        @join_on = constraints.map do |left, right|
          left = project_on(base_table, left)
          right = project_on(@table, right)
          left.eq(right)
        end
      end

      # Save the query command to be performand
      def query(relation)
        @query = relation
      end

      # Build the statement for a given arel
      def build_arel(arel, columns)
        query = @query.clone
        query_table = query.arel_table

        # Set query columns and expose columns
        projected_columns = @attributes.map do |left, right|
          query = query.select(project_on(query_table, left).as(right.to_s))
          project_on(@table, right)
        end
        columns.concat projected_columns

        # Get all extra join attributes from the right table and put them on
        # the select query so they are exposed
        (@join_attributes - @attributes.values).map do |right|
          query = query.select(project_on(query_table, right))
        end

        # Build the join for this statement
        arel.join(@table, arel_join).on(*@join_on)

        # Return the subquery for this statement
        Arel::Nodes::As.new @table, begin
          case query
          when ActiveRecord::Relation
            query.send(:build_arel)
          when String
            Arel::Nodes::SqlLiteral.new(query)
          end
        end
      end

      private

        # Get a column projection on a table
        def project_on(table, column)
          if column.to_s.include?('.')
            table, column = column.split('.')
            table = Arel::Table.new(table)
          end

          table[column]
        end

        # Get the class of the join on arel
        def arel_join
          case @join_type
          when :inner then Arel::Nodes::InnerJoin
          when :left then Arel::Nodes::OuterJoin
          when :right then Arel::Nodes::RightOuterJoin
          when :full then Arel::Nodes::FullOuterJoin
          else
            raise ArgumentError, <<-MSG.gsub(/^ +| +$|\n/, '')
              The '#{@join_type}' is not implemented as a join type.
            MSG
          end
        end

    end
  end
end
