
require_relative 'relation/distinct_on'

module Torque
  module PostgreSQL
    module Relation

      include DistinctOn

      # Resolve column definition up to second value.
      # For example, based on Post model:
      #
      #   resolve_column(['name', :title])
      #   # Returns ['name', '"posts"."title"']
      #
      #   resolve_column([:title, {authors: :name}])
      #   # Returns ['"posts"."title"', '"authors"."name"']
      #
      #   resolve_column([{authors: [:name, :age]}])
      #   # Returns ['"authors"."name"', '"authors"."age"']
      def resolve_column(list, base = false)
        base = resolve_base_table(base)

        list.map do |item|
          case item
          when String
            Arel::Nodes::SqlLiteral.new(klass.send(:sanitize_sql, item.to_s))
          when Symbol
            base ? base.arel_attribute(item) : klass.arel_attribute(item)
          when Array
            resolve_column(item, base)
          when Hash
            raise ArgumentError, "Unsupported Hash for attributes on third level" if base
            item.map do |key, other_list|
              other_list = [other_list] unless other_list.kind_of? Enumerable
              resolve_column(other_list, key)
            end
          else
            raise ArgumentError, "Unsupported argument type: #{value} (#{value.class})"
          end
        end.flatten
      end

      # Get the TableMetadata from a relation
      def resolve_base_table(relation)
        return unless relation

        table = predicate_builder.send(:table)
        if table.associated_with?(relation)
          table.associated_table(relation).send(:klass)
        else
          raise ArgumentError, "Relation for #{relation} not found on #{klass}"
        end
      end

    end

    ActiveRecord::Relation.include Relation
  end
end
