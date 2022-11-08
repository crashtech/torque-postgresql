# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Migration
      module CommandRecorder

        # Records the rename operation for types.
        def rename_type(*args, &block)
          record(:rename_type, args, &block)
        end

        # Inverts the type name.
        def invert_rename_type(args)
          [:rename_type, args.reverse]
        end

        # Records the creation of the enum to be reverted.
        def create_enum(*args, &block)
          record(:create_enum, args, &block)
        end

        # Inverts the creation of the enum.
        def invert_create_enum(args)
          [:drop_type, [args.first]]
        end

        # Records the creation of the struct to be reverted.
        def create_struct(*args, &block)
          record(:create_struct, args, &block)
        end
        def invert_create_struct(*args)
          [:drop_type, [args.first]]
        end

      end

      ActiveRecord::Migration::CommandRecorder.include CommandRecorder
    end
  end
end
