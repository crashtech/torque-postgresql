# frozen_string_literal: true

module Torque
  module PostgreSQL
    class AuxiliaryStatement
      class Recursive < AuxiliaryStatement

        private

          # Build the string or arel query
          def build_query(base)
            # Expose columns and get the list of the ones for select
            columns = expose_columns(base, @query.try(:arel_table))
            sub_columns = columns.dup
            union_all = settings.all.present?

            # Build any extra columns that are dynamic and from the recursion
            extra_columns(base, columns, sub_columns)
            type = union_all ? 'all' : ''

            # Prepare the query depending on its type
            if @query.is_a?(String)
              args = @args.each_with_object({}) { |h, (k, v)| h[k] = base.connection.quote(v) }
              ::Arel.sql("(#{@query} UNION #{type.upcase} #{@sub_query})" % args)
            elsif relation_query?(@query)
              @query = @query.where(@where) if @where.present?
              @bound_attributes.concat(@query.send(:bound_attributes))
              @bound_attributes.concat(@sub_query.send(:bound_attributes))

              sub_query = @sub_query.select(*columns).arel
              sub_query.from([@sub_query.arel_table, table])

              @query.select(*columns).arel.union(type, sub_query)
            else
              raise ArgumentError, <<-MSG.squish
                Only String and ActiveRecord::Base objects are accepted as query objects,
                #{@query.class.name} given for #{self.class.name}.
              MSG
            end
          end

          # Setup the statement using the class configuration
          def prepare(base)
            super

            prepare_sub_query(base)
          end

          # Make sure that both parts of the union are ready
          def prepare_sub_query(base)
            @sub_query = settings.sub_query

            raise ArgumentError, <<-MSG.squish if @sub_query.nil? && @query.is_a?(String)
              Unable to generate sub query from a string query. Please provide a `sub_query`
              property on the "#{table_name}" settings.
            MSG

            if @sub_query.nil?
              left, right = @connect = settings.connect.to_a.first.map(&:to_s)
              @sub_query = @query.where(@query.arel_table[right].eq(table[left]))
              @query = @query.where(right => nil) unless @query.where_values_hash.key?(right)
            else
              # Call a proc to get the real sub query
              if @sub_query.respond_to?(:call)
                call_args = @sub_query.try(:arity) === 0 ? [] : [OpenStruct.new(@args)]
                @sub_query = @sub_query.call(*call_args)
                @args = []
              end

              # Manually set the query table when it's not an relation query
              @sub_query_table = settings.sub_query_table unless relation_query?(@sub_query)
            end
          end

          # Add depth and path if they were defined in settings
          def extra_columns(base, columns, sub_columns)
            return if @query.is_a?(String) || @sub_query.is_a?(String)

            # Add the connect attribute to the query
            if defined?(@connect)
              columns.unshift(@query.arel_table[@connect[0]])
              sub_columns.unshift(@sub_query.arel_table[@connect[0]])
            end

            # Build a column to represent the depth of the recursion
            if settings.depth?
              col = table[settings.depth]
              base.select_extra_values += [col]

              columns << settings.sql('0').as(settings.depth)
              sub_columns << (col + settings.sql('1')).as(settings.depth)
            end

            # Build a column to represent the path of the record access
            if settings.path?
              name, source = settings.path
              source ||= @connect[0]

              raise ArgumentError, <<-MSG.squish if source.nil?
                Unable to generate path without providing a source or connect setting.
              MSG

              col = table[name]
              base.select_extra_values += [col]
              parts = [col, @sub_query.arel_table[source].cast(:varchar)]

              columns << ::Arel.array([col]).cast(:varchar, true).as(name)
              sub_columns << ::Arel.named_function(:array_append, parts)
            end
          end

      end
    end
  end
end
