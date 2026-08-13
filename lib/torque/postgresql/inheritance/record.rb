# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Inheritance
      module Record

        # Whether the record was loaded from one of its ancestor tables and
        # therefore is missing the columns that only exist on its own table
        def partial_record?
          @partial_record == true
        end

        # Reload always queries the record's own table, which produces a
        # complete and writable record
        def reload(*)
          return super unless partial_record?

          super.tap { mark_as_full_record! }
        end

        # Deleting a row only needs its primary key, so the missing columns of
        # a partial record are no reason to refuse it
        def destroy
          return super unless partial_record?

          without_readonly { super }
        end

        private

          def without_readonly
            @readonly = false
            yield
          ensure
            @readonly = true
          end

          def mark_as_partial_record!
            @partial_record = true
            readonly!
          end

          def mark_as_full_record!
            @partial_record = false
            @readonly = false
          end

      end
    end
  end
end
