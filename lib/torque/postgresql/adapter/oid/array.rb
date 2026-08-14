# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module OID
        module Array
          def force_equality?(value)
            PostgreSQL.config.predicate_builder.handle_array_attributes ? false : super
          end

          private

            # A label path is an Array of labels, so the regular recursion would
            # take each of its labels as another dimension of the column. Paths
            # are a single value to PostgreSQL, which means that the entries of
            # the array are never a dimension of their own
            def type_cast_array(value, method)
              return super unless path_subtype?
              return subtype.public_send(method, value) unless value.is_a?(::Array)

              value.map { |item| subtype.public_send(method, item) }
            end

            def path_subtype?
              PostgreSQL.config.ltree.enabled && subtype.is_a?(Ltree)
            end
        end

        ::ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array.prepend(Array)
      end
    end
  end
end
