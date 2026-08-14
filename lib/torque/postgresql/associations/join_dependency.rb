# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Associations
      module JoinDependency
        def apply_column_aliases(relation)
          result = super
          return result unless relation.from_clause.empty?

          relation._select!(root_record_class_marker) if cast_join_root?(relation)
          relation._select!(-> { joined_record_class_markers })
          result
        end

        private

          def cast_join_root?(relation)
            return false if relation.itself_only_value === true
            return false unless join_root_alias

            join_root.base_klass.physically_inheritances?
          end

          def root_record_class_marker
            table = join_root.base_klass.arel_table
            table['tableoid'].pg_cast(:regclass).as(record_class_column_name)
          end

          # The root is projected under its own name and picked up by the
          # column sweep in #instantiate, which only ever feeds the root. Every
          # other join part has to carry the marker inside its own set of
          # aliases, since that is all #extract_record ever reads
          def joined_record_class_markers
            markers = join_root.each_with_index.map do |join_part, index|
              next if index.zero? || !join_part.base_klass.physically_inheritances?
              next if (columns = aliases.column_aliases(join_part)).blank?

              column_alias = "#{columns.first.alias[/\At\d+/]}_r#{columns.size}"
              columns << ::ActiveRecord::Associations::JoinDependency::Aliases::Column
                .new(record_class_column_name, column_alias)

              join_part.table['tableoid'].pg_cast(:regclass).as(column_alias)
            end

            markers.compact
          end

          def record_class_column_name
            ::ActiveRecord::Relation._record_class_column_name
          end
      end
    end
  end
end
