# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Validations

      # Checks if the objects nested into an attribute are valid, adding a
      # single error to the attribute when any of them is not. It takes the
      # regular +allow_nil+ and +allow_blank+ options, which is how values that
      # are merely absent are left out of it
      #
      # Example:
      #   validates :home, nested: true
      #   validates :settings, nested: true, allow_blank: true
      class NestedValidator < ActiveModel::EachValidator
        def validate_each(record, attribute, value)
          invalid = Array.wrap(value).any? do |item|
            item.respond_to?(:invalid?) && item.invalid?
          end

          record.errors.add(attribute, :invalid) if invalid
        end
      end

    end

    ::ActiveRecord::Base.include(Validations)
  end
end
