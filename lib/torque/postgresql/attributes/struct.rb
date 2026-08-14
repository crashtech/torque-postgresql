# frozen_string_literal: true

require_relative 'base'

module Torque
  module PostgreSQL
    module Attributes
      class Struct < Base
        # ActiveModel keeps a sentinel object as the original value of a
        # property that was never written to, which leaks into +changes+ and
        # into anything built on top of it, so it reads as nil instead
        class Uninitialized < ActiveModel::Attribute.const_get(:Uninitialized)
          def original_value
          end
        end

        class << self
          attr_writer :strict

          # Whether properties that are not declared by the class are rejected
          def strict?
            return !!@strict if defined?(@strict)
            return !!superclass.strict? if superclass.respond_to?(:strict?)

            PostgreSQL.config.struct.default_strict
          end

          # Declared properties without a default are uninitialized, so that
          # they are absent from the document until they are written to
          def _default_attributes
            @_struct_default_attributes ||= super.map do |attribute|
              next attribute if attribute.is_a?(ActiveModel::Attribute::UserProvidedDefault)
              Uninitialized.new(attribute.name, attribute.type)
            end
          end

          # Provide a method on the given class to setup which columns are
          # backed by a struct class
          def include_on(klass, method_name = nil)
            method_name ||= PostgreSQL.config.struct.base_method
            klass.define_singleton_method(method_name) do |column, struct_klass, **options|
              Struct.build_on(self, column, struct_klass, **options)
            rescue Interrupt
              # Not able to build the attribute, maybe pending migrations
            end
          end

          # Setup the struct column on the given model, adding the proper
          # attribute type, default, validation, and delegations
          def build_on(model, column, klass, default: nil, array: nil, delegate: nil, backfill: nil, strict: nil)
            return unless model.table_exists?

            column = column.to_s
            has_encryption = model.respond_to?(:encrypted_attributes) &&
              model.encrypted_attributes&.include?(column.to_sym)

            raise ArgumentError, <<~MSG.squish if has_encryption
              Unable to setup the struct column "#{column}" on #{model.name}
              because the column is encrypted. Encryption is supported on
              individual struct attributes instead.
            MSG

            info = model.columns_hash[column]
            return if info.nil?

            raise ArgumentError, <<~MSG.squish unless %i[json jsonb].include?(info.type)
              Unable to setup the struct column "#{column}" on #{model.name}
              because #{info.sql_type} columns cannot hold a document.
            MSG

            klass = klass.constantize if klass.is_a?(String) || klass.is_a?(Symbol)
            klass.strict = !!strict if !strict.nil? && klass.respond_to?(:strict=)

            type =
              if array
                Adapter::OID::StructList.new(klass, type: info.type, backfill: backfill)
              else
                Adapter::OID::Struct.new(klass, type: info.type, backfill: backfill)
              end

            type = Adapter::OID::StructSet.new(type) if info.array?

            # Defaults that can be composed from the record have to be resolved
            # on it, all the others are plain attribute defaults
            if default.is_a?(Proc) || default.is_a?(Symbol)
              model.attribute(column, type)
              resolve_default_on(model, column, default)
            else
              model.attribute(column, type, default: -> { default&.deep_dup || type.blank_document })
            end

            Array.wrap(delegate).flat_map do |property|
              [property, "#{property}="]
            end.then do |delegations|
              model.delegate(*delegations, to: column) if delegations.any?
            end

            model.validates(column, nested: true, allow_blank: true)
          end

          private

            def reset_default_attributes!
              @_struct_default_attributes = nil
              super
            end

            # Write the default on the record, as soon as it is initialized, so
            # that it can be composed from the record and properly stored
            def resolve_default_on(model, column, default)
              model.after_initialize do
                next unless new_record?
                next unless read_attribute_before_type_cast(column).nil?
                next if attribute_changed?(column)

                value = default.is_a?(Proc) ? instance_exec(&default) : public_send(default)
                write_attribute(column, value)
              end
            end
        end

        # Properties that are not declared by the class are kept as they are,
        # without any type, which is only allowed when the class is not strict
        def attribute_writer_missing(name, value)
          return super if self.class.strict?

          name = name.to_s
          attribute = @attributes[name] if @attributes.key?(name)
          attribute ||= ActiveModel::Attribute.from_database(name, nil, ActiveModel::Type.default_value)
          @attributes[name] = attribute.with_value_from_user(value)
        end
      end
    end

    Struct = Attributes::Struct
  end
end
