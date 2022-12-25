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
