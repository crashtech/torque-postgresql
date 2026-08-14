# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Attributes
      # Brings Rails' own +enum+ to classes that are not backed by a table, which
      # means everything that depends on a record being persisted, or on a
      # relation, is left out. Only the +value?+ methods are generated
      module SimpleEnum
        extend ActiveSupport::Concern

        # Replaces the module that Rails uses to generate the methods of an
        # enum, so that only the ones that make sense here are defined
        class Methods < Module
          def initialize(klass)
            @klass = klass
          end

          private

            attr_reader :klass

            def define_enum_methods(name, value_method_name, value, _scopes, instance_methods)
              return unless instance_methods

              klass.send(:detect_enum_conflict!, name, "#{value_method_name}?")
              define_method("#{value_method_name}?") do
                @attributes[name].value_for_database == value
              end
            end
        end

        included do
          class_attribute :defined_enums, instance_writer: false, default: {}
        end

        class_methods do
          include ActiveRecord::Enum

          # Scopes require a relation, so they are never an option here
          def enum(name, values = nil, **options)
            super(name, values, **options, scopes: false)
          end

          private

            def _enum_methods_module
              @_enum_methods_module ||= begin
                mod = Methods.new(self)
                include mod
                mod
              end
            end

            # There are no dangerous class methods to check against, since enums
            # never define one, and anything that the base class already
            # provides is off limits
            def detect_enum_conflict!(enum_name, method_name, klass_method = false)
              return if klass_method
              return unless Base.method_defined?(method_name) ||
                Base.private_method_defined?(method_name)

              raise ArgumentError, <<~MSG.squish
                You tried to define an enum named "#{enum_name}" on #{name}, but
                it generates a method "#{method_name}" that is already defined.
              MSG
            end
        end
      end
    end
  end
end
