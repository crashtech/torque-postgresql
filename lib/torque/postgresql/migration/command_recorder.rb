# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Migration
      module CommandRecorder

        # Records the rename operation for types
        def rename_type(*args, &block)
          record(:rename_type, args, &block)
        end

        # Inverts the type rename operation
        def invert_rename_type(args)
          [:rename_type, args.reverse]
        end

        # Records the creation of a composite type
        def create_composite_type(*args, &block)
          record(:create_composite_type, args, &block)
        end

        # Inverts the creation of a composite type
        def invert_create_composite_type(args)
          options = args.second.try(:slice, :schema) || {}
          [:drop_type, [args.first, options]]
        end

        # Records changes to a composite type, which cannot be inverted for the
        # same reason as +change_table+
        def change_composite_type(*args, &block)
          record(:change_composite_type, args, &block)
        end

        # Records a column being added to a composite type
        def add_composite_column(*args, &block)
          record(:add_composite_column, args, &block)
        end

        # Inverts a column being added to a composite type
        def invert_add_composite_column(args)
          [:remove_composite_column, args]
        end

        # Records a column being removed from a composite type
        def remove_composite_column(*args, &block)
          record(:remove_composite_column, args, &block)
        end

        # Inverts a column being removed from a composite type, which is only
        # possible when its type was informed
        def invert_remove_composite_column(args)
          raise ActiveRecord::IrreversibleMigration, <<~MSG.squish if args.third.nil?
            remove_composite_column is only reversible if given a type.
          MSG

          [:add_composite_column, args]
        end

        # Records the type of a column being changed, which cannot be inverted
        # because the previous type is unknown
        def change_composite_column(*args, &block)
          record(:change_composite_column, args, &block)
        end

        # Records a column of a composite type being renamed
        def rename_composite_column(*args, &block)
          record(:rename_composite_column, args, &block)
        end

        # Inverts a column of a composite type being renamed
        def invert_rename_composite_column(args)
          [:rename_composite_column, [args.first, args.third, args.second, *args[3..]]]
        end

        # Records the spread of features into inherited tables. While reverting,
        # the pruning form goes to the front of the list, which is played back
        # reversed, so the children are only pruned once everything else the
        # migration did to their parents has been undone
        def sync_inheritance_features(*args, &block)
          return record(:sync_inheritance_features, args, &block) unless reverting

          commands.unshift(inverse_of(:sync_inheritance_features, args, &block))
        end
        ruby2_keywords(:sync_inheritance_features)

        # Inverts the spread of features by running it again while pruning, so
        # the children converge back to whatever the parent looks like
        def invert_sync_inheritance_features(args)
          options = args.extract_options!.merge(prune: true)
          [:sync_inheritance_features, [*args, Hash.ruby2_keywords_hash(options)]]
        end

        # Records the creation of a schema
        def create_schema(*args, &block)
          record(:create_schema, args, &block)
        end

        # Inverts the creation of a schema
        def invert_create_schema(args)
          [:drop_schema, [args.first]]
        end

      end

      ActiveRecord::Migration::CommandRecorder.include CommandRecorder
    end
  end
end
