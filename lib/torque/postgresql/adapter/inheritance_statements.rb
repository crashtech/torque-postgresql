# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module InheritanceStatements

        # Copies created by a sync are named after this, which is how they are
        # told apart from anything written by hand
        SYNC_MARKER = 'sync_inh_'

        SYNC_FEATURES = %i[
          primary_key indexes unique_constraints exclusion_constraints foreign_keys
        ].freeze

        # PostgreSQL only propagates columns, their defaults and their check
        # constraints to inherited tables. This copies over everything else that
        # Rails has a DSL for, from +table_name+ down to its children
        #
        # Features default to +true+, so passing one as +false+ excludes it.
        # Passing any of them as +true+ instead selects only those
        #
        # Example:
        #   sync_inheritance_features :activities
        #   sync_inheritance_features :activities, %i[activity_books]
        #   sync_inheritance_features :activities, primary_key: false
        #   sync_inheritance_features :activities, prune: true
        def sync_inheritance_features(table_name, children = nil, prune: false, **features)
          features = sync_inheritance_selection(features)

          sync_inheritance_tree(table_name, children).each do |child, parents|
            sync_inheritance_into(child, parents, features, prune)
          end
        end

        private

          # Resolves which tables to write to, and where each of them pulls from,
          # with ancestors always coming before their own descendants
          def sync_inheritance_tree(table_name, children)
            table_name = table_name.to_s
            dependencies = inherited_tables
            descendants = sync_inheritance_descendants(dependencies, table_name)

            targets = descendants
            unless children.nil?
              children = Array.wrap(children).map(&:to_s)
              unknown = children - descendants
              raise ArgumentError, <<~MSG.squish if unknown.any?
                #{unknown.to_sentence} #{unknown.one? ? 'does' : 'do'} not inherit
                from #{table_name}
              MSG

              targets = descendants & children
            end

            scope = [table_name] + descendants
            targets.map { |child| [child, dependencies[child] & scope] }
          end

          # Walks the inheritance graph breadth-first, so that every table shows
          # up only after all of its own ancestors
          def sync_inheritance_descendants(dependencies, table_name)
            children = {}
            dependencies.each do |child, parents|
              parents.each { |parent| (children[parent] ||= []) << child }
            end

            result = []
            queue = (children[table_name] || []).dup

            while (item = queue.shift)
              next if result.include?(item)

              result << item
              queue.concat(children[item] || [])
            end

            result
          end

          # Turns what was asked for into a decision for every single feature
          def sync_inheritance_selection(features)
            features = {} if features == true
            unknown = features.keys - SYNC_FEATURES
            raise ArgumentError, <<~MSG.squish if unknown.any?
              Unknown inheritance #{'feature'.pluralize(unknown.size)} #{unknown.to_sentence}
            MSG

            return SYNC_FEATURES.index_with(true) if features.blank?
            return SYNC_FEATURES.index_with { |name| features.fetch(name, false) } \
              if features.value?(true)

            SYNC_FEATURES.index_with { |name| features.fetch(name, true) }
          end

          def sync_inheritance_into(child, parents, features, prune)
            return if parents.blank?

            sync_inheritance_primary_key(child, parents) if features[:primary_key]
            sync_inheritance_unique_constraints(child, parents, prune) \
              if features[:unique_constraints]
            sync_inheritance_exclusion_constraints(child, parents, prune) \
              if features[:exclusion_constraints]
            sync_inheritance_indexes(child, parents, features, prune) if features[:indexes]
            sync_inheritance_foreign_keys(child, parents, prune) if features[:foreign_keys]
          end

          # The only copy that cannot carry the marker, since PostgreSQL names it
          # after the table and Rails has no way to dump that name back. That is
          # why it is also the only one that is never pruned
          def sync_inheritance_primary_key(child, parents)
            return if primary_keys(child).present?

            parent = parents.find { |item| primary_keys(item).present? }
            return if parent.nil?

            columns = primary_keys(parent).map { |column| quote_column_name(column) }
            execute(<<~SQL.squish)
              ALTER TABLE #{quote_table_name(child)} ADD PRIMARY KEY (#{columns.join(', ')})
            SQL
          end

          def sync_inheritance_indexes(child, parents, features, prune)
            existing = indexes(child)
            expected = {}

            parents.each do |parent|
              skip = sync_inheritance_constraint_indexes(parent, features)
              indexes(parent).each do |index|
                next if skip.include?(index.name)

                expected[sync_inheritance_name(child, parent, index.name)] ||= index
              end
            end

            expected.each do |name, index|
              next if existing.any? { |item| item.name == name || sync_inheritance_index?(item, index) }

              add_index(child, index.columns, name: name, **sync_inheritance_index_options(index))
            end

            return unless prune

            # An index that backs a constraint can only leave with it
            guarded = sync_inheritance_constraint_indexes(child)
            sync_inheritance_stale(existing, expected).each do |name|
              remove_index(child, name: name) unless guarded.include?(name)
            end
          end

          def sync_inheritance_unique_constraints(child, parents, prune)
            existing = unique_constraints(child)
            expected = {}

            parents.each do |parent|
              unique_constraints(parent).each do |item|
                expected[sync_inheritance_name(child, parent, item.name)] ||= item
              end
            end

            expected.each do |name, item|
              next if existing.any? { |other| other.name == name || other.column == item.column }

              add_unique_constraint(child, item.column, name: name,
                nulls_not_distinct: item.nulls_not_distinct, deferrable: item.deferrable)
            end

            return unless prune
            sync_inheritance_stale(existing, expected).each do |name|
              remove_constraint(child, name)
            end
          end

          def sync_inheritance_exclusion_constraints(child, parents, prune)
            existing = exclusion_constraints(child)
            expected = {}

            parents.each do |parent|
              exclusion_constraints(parent).each do |item|
                expected[sync_inheritance_name(child, parent, item.name)] ||= item
              end
            end

            expected.each do |name, item|
              next if existing.any? { |other| other.name == name || sync_inheritance_exclusion?(other, item) }

              add_exclusion_constraint(child, item.expression, name: name,
                using: item.using, where: item.where, deferrable: item.deferrable)
            end

            return unless prune
            sync_inheritance_stale(existing, expected).each do |name|
              remove_constraint(child, name)
            end
          end

          def sync_inheritance_foreign_keys(child, parents, prune)
            existing = foreign_keys(child)
            expected = {}

            parents.each do |parent|
              foreign_keys(parent).each do |item|
                expected[sync_inheritance_name(child, parent, item.name)] ||= item
              end
            end

            expected.each do |name, item|
              next if existing.any? { |other| other.name == name || sync_inheritance_foreign_key?(other, item) }

              options = item.options.slice(:column, :primary_key, :on_delete, :on_update, :deferrable)
              add_foreign_key(child, item.to_table, name: name, **options)
            end

            return unless prune
            sync_inheritance_stale(existing, expected).each do |name|
              remove_constraint(child, name)
            end
          end

          # Every copy is named after the marker plus a digest of where it came
          # from and where it went, which keeps it identical across databases and
          # always well below the identifier limit
          def sync_inheritance_name(child, parent, source)
            digest = OpenSSL::Digest::SHA256.hexdigest("#{child}/#{parent}/#{source}")
            "#{SYNC_MARKER}#{digest.first(10)}"
          end

          def sync_inheritance_copy?(name)
            name.to_s.start_with?(SYNC_MARKER)
          end

          # Copies whose source is gone from the parent, which is all that a
          # prune is ever allowed to drop
          def sync_inheritance_stale(existing, expected)
            existing.filter_map do |item|
              item.name if sync_inheritance_copy?(item.name) && !expected.key?(item.name)
            end
          end

          # PostgreSQL names the index that backs a constraint after the
          # constraint itself, and +indexes+ hands those back along with the
          # regular ones. Adding the constraint recreates them, so they are only
          # skipped when that constraint is being copied as well. Without any
          # feature given, every one of them is listed
          def sync_inheritance_constraint_indexes(table_name, features = nil)
            names = []
            names.concat(unique_constraints(table_name).map(&:name)) \
              if features.nil? || features[:unique_constraints]
            names.concat(exclusion_constraints(table_name).map(&:name)) \
              if features.nil? || features[:exclusion_constraints]
            names
          end

          def sync_inheritance_index_options(index)
            {
              unique: index.unique,
              where: index.where,
              using: index.using,
              include: index.include,
              nulls_not_distinct: index.nulls_not_distinct,
              order: index.orders,
              opclass: index.opclasses,
            }.compact_blank
          end

          def sync_inheritance_index?(current, source)
            current.columns == source.columns && current.unique == source.unique &&
              current.where == source.where && current.using == source.using
          end

          def sync_inheritance_exclusion?(current, source)
            current.expression == source.expression && current.using == source.using &&
              current.where == source.where
          end

          def sync_inheritance_foreign_key?(current, source)
            current.to_table == source.to_table &&
              current.options[:column] == source.options[:column] &&
              current.options[:primary_key] == source.options[:primary_key]
          end

          # Tells whether the primary key of the given table is the one it got
          # from a parent, which is the only case the dumper has to describe
          # through the +sync+ option
          def sync_inheritance_parent_primary_key?(table_name)
            keys = primary_keys(table_name)
            return false if keys.empty?

            parents = inherited_table_names(table_name)
            parents.any? { |parent| primary_keys(parent) == keys }
          end

      end
    end
  end
end
