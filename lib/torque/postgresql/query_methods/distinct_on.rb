module Torque
  module Postgresql
    module QueryMethods

      module DistinctOn

        attr_accessor :distinct_on_value

        # def self.extended(base)
        #   base.class_eval do

        #     def build_arel
        #       raise 'Here!'
        #     end

        #   end
        # end

        # Specifies whether the records should be unique or not by a given set of fields.
        # For example:
        #
        #   User.distinct_on(:name)
        #   # Returns 1 record per distinct name
        #
        #   User.distinct_on(:name, :email)
        #   # Returns 1 record per distinct name and email
        #
        #   User.distinct_on(false)
        #   # You can also remove the uniqueness
        def distinct_on(*value)
          spawn.distinct_on!(*value)
        end

        # Like #distinct_on, but modifies relation in place.
        def distinct_on!(*value)
          self.distinct_on_value = value
          self
        end

        private

          # Hook arel build to add the distinct on clause
          def build_arel
            arel = super

            value = self.distinct_on_value
            arel.distinct_on(resolve_column(value)) unless value.nil?
            arel
          end

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

      ActiveRecord::Relation.send :include, DistinctOn

    end
  end
end
