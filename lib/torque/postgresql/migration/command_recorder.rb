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
