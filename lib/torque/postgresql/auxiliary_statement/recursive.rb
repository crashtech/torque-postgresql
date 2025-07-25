# frozen_string_literal: true

module Torque
  module PostgreSQL
    class AuxiliaryStatement
      class Recursive < AuxiliaryStatement
        # Setup any additional option in the recursive mode
        def initialize(*, **options)
          super

          @connect = options[:connect]&.to_a&.first
          @union_all = options[:union_all]
          @sub_query = options[:sub_query]

          if options.key?(:with_depth)
            @depth = options[:with_depth].values_at(:name, :start, :as)
            @depth[0] ||= 'depth'
          end

          if options.key?(:with_path)
            @path = options[:with_path].values_at(:name, :source, :as)
            @path[0] ||= 'path'
          end
        end

        private

          # Build the string or arel query
          def build_query(base)
            # Expose columns and get the list of the ones for select
            columns = expose_columns(base, @query.try(:arel_table))
            sub_columns = columns.dup
            type = @union_all.present? ? 'all' : ''

            # Build any extra columns that are dynamic and from the recursion
            extra_columns(base, columns, sub_columns)

            # Prepare the query depending on its type
            if @query.is_a?(String) && @sub_query.is_a?(String)
              args = @args.each_with_object({}) { |h, (k, v)| h[k] = base.connection.quote(v) }
              ::Arel.sql("(#{@query} UNION #{type.upcase} #{@sub_query})" % args)
            elsif relation_query?(@query)
              @query = @query.where(@where) if @where.present?
              @bound_attributes.concat(@query.send(:bound_attributes))

              if relation_query?(@sub_query)
                @bound_attributes.concat(@sub_query.send(:bound_attributes))

                sub_query = @sub_query.select(*sub_columns).arel
                sub_query.from([@sub_query.arel_table, table])
              else
                sub_query = ::Arel.sql(@sub_query)
              end

              @query.select(*columns).arel.union(type, sub_query)
            else
              raise ArgumentError, <<-MSG.squish
                Only String and ActiveRecord::Base objects are accepted as query and sub query
                objects, #{@query.class.name} given for #{self.class.name}.
              MSG
            end
          end

          # Setup the statement using the class configuration
          def prepare(base, settings)
            super

            prepare_sub_query(base, settings)
          end

          # Make sure that both parts of the union are ready
          def prepare_sub_query(base, settings)
            @union_all = settings.union_all if @union_all.nil?
            @sub_query ||= settings.sub_query
            @depth ||= settings.depth
            @path ||= settings.path

            # Collect the connection
            @connect ||= settings.connect || begin
              key = base.primary_key
              [key.to_sym, :"parent_#{key}"] unless key.nil?
            end

            raise ArgumentError, <<-MSG.squish if @sub_query.nil? && @query.is_a?(String)
              Unable to generate sub query from a string query. Please provide a `sub_query`
              property on the "#{table_name}" settings.
            MSG

            if @sub_query.nil?
              raise ArgumentError, <<-MSG.squish if @connect.blank?
                Unable to generate sub query without setting up a proper way to connect it
                with the main query. Please provide a `connect` property on the "#{table_name}"
                settings.
              MSG

              left, right = @connect.map(&:to_s)
              condition = @query.arel_table[right].eq(table[left])

              if @query.where_values_hash.key?(right)
                @sub_query = @query.unscope(where: right.to_sym).where(condition)
              else
                @sub_query = @query.where(condition)
                @query = @query.where(right => nil)
              end
            elsif @sub_query.respond_to?(:call)
              # Call a proc to get the real sub query
              call_args = @sub_query.try(:arity) === 0 ? [] : [OpenStruct.new(@args)]
              @sub_query = @sub_query.call(*call_args)
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
            if @depth.present?
              name, start, as = @depth
              col = table[name]
              base.select_extra_values += [col.as(as)] unless as.nil?

              columns << ::Arel.sql(start.to_s).as(name)
              sub_columns << (col + ::Arel.sql('1')).as(name)
            end

            # Build a column to represent the path of the record access
            if @path.present?
              name, source, as = @path
              source = @query.arel_table[source || @connect[0]]

              col = table[name]
              base.select_extra_values += [col.as(as)] unless as.nil?
              parts = [col, source.pg_cast(:varchar)]

              columns << ::Arel.array([source]).pg_cast(:varchar, true).as(name)
              sub_columns << ::Arel::Nodes::NamedFunction.new('array_append', parts).as(name)
            end
          end

      end
    end
  end
end
