# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Attributes
      class Enum < String
        include Comparable

        class EnumError < ArgumentError; end

        LAZY_VALUE = 0.chr

        class << self
          include Enumerable

          delegate :each, :sample, :size, :length, to: :members

          # Find or create the class that will handle the value
          def lookup(name)
            const     = name.to_s.camelize
            namespace = Torque::PostgreSQL.config.enum.namespace

            return namespace.const_get(const) if namespace.const_defined?(const)
            namespace.const_set(const, Class.new(Enum))
          end

          # Provide a method on the given class to setup which enums will be
          # manually initialized
          def include_on(klass, method_name = nil)
            method_name ||= Torque::PostgreSQL.config.enum.base_method
            Builder.include_on(klass, method_name, Builder::Enum) do |builder|
              defined_enums[builder.attribute.to_s] = builder.subtype.klass
            end
          end

          # Overpass new so blank values return only nil
          def new(value)
            return Lazy.new(self, LAZY_VALUE) if value.blank?
            super
          end

          # Load the list of values in a lazy way
          def values
            @values ||= self == Enum ? nil : begin
              connection.enum_values(type_name).freeze
            end
          end

          # List of valus as symbols
          def keys
            values.map(&:to_sym)
          end

          # Different from values, it returns the list of items already casted
          def members
            values.map(&method(:new))
          end

          # Get the list of the values translated by I18n
          def texts
            members.map(&:text)
          end

          # Get a list of values translated and ready for select
          def to_options
            texts.zip(values)
          end

          # Fetch a value from the list
          # see https://github.com/rails/rails/blob/v5.0.0/activerecord/lib/active_record/fixtures.rb#L656
          # see https://github.com/rails/rails/blob/v5.0.0/activerecord/lib/active_record/validations/uniqueness.rb#L101
          def fetch(value, *)
            new(value.to_s) if values.include?(value)
          end
          alias [] fetch

          # Get the type name from its class name
          def type_name
            @type_name ||= self.name.demodulize.underscore
          end

          # Check if the value is valid
          def valid?(value)
            return false if self == Enum
            return true if value.equal?(LAZY_VALUE)
            self.values.include?(value.to_s)
          end

          # Build an active record scope for a given atribute agains a value
          def scope(attribute, value)
            attribute.eq(value)
          end

          private

            # Allows checking value existance
            def respond_to_missing?(method_name, include_private = false)
              valid?(method_name) || super
            end

            # Allow fast creation of values
            def method_missing(method_name, *arguments)
              return super if self == Enum
              valid?(method_name) ? new(method_name.to_s) : super
            end

            # Get a connection based on its name
            def connection
              ::ActiveRecord::Base.connection
            end

        end

        # Override string initializer to check for a valid value
        def initialize(value)
          str_value = value.is_a?(Numeric) ? self.class.values[value.to_i] : value.to_s
          raise_invalid(value) unless self.class.valid?(str_value)
          super(str_value)
        end

        # Allow comparison between values of the same enum
        def <=>(other)
          raise_comparison(other) if other.is_a?(Enum) && other.class != self.class

          case other
          when Numeric, Enum  then to_i <=> other.to_i
          when String, Symbol then to_i <=> self.class.values.index(other.to_s)
          else raise_comparison(other)
          end
        end

        # Only allow value comparison with values of the same class
        def ==(other)
          (self <=> other) == 0
        rescue EnumError
          false
        end
        alias eql? ==

        # Since it can have a lazy value, nil can be true here
        def nil?
          self == LAZY_VALUE
        end
        alias empty? nil?

        # It only accepts if the other value is valid
        def replace(value)
          raise_invalid(value) unless self.class.valid?(value)
          super
        end

        # Get a translated version of the value
        def text(attr = nil, model = nil)
          keys = i18n_keys(attr, model) << self.underscore.humanize
          ::I18n.translate(keys.shift, default: keys)
        end

        # Change the string result for lazy value
        def to_s
          nil? ? '' : super
        end

        # Get the index of the value
        def to_i
          self.class.values.index(self)
        end

        # Change the inspection to show the enum name
        def inspect
          nil? ? 'nil' : ":#{to_s}"
        end

        private

          # Get the i18n keys to check
          def i18n_keys(attr = nil, model = nil)
            values = { type: self.class.type_name, value: to_s }
            list_from = :i18n_type_scopes

            if attr && model
              values[:attr] = attr
              values[:model] = model.model_name.i18n_key
              list_from = :i18n_scopes
            end

            Torque::PostgreSQL.config.enum.send(list_from).map do |key|
              (key % values).to_sym
            end
          end

          # Check for valid '?' and '!' methods
          def respond_to_missing?(method_name, include_private = false)
            name = method_name.to_s

            return true if name.chomp!('?')
            name.chomp!('!') && self.class.valid?(name)
          end

          # Allow '_' to be associated to '-'
          def method_missing(method_name, *arguments)
            name = method_name.to_s

            if name.chomp!('?')
              self == name
            elsif name.chomp!('!')
              replace(name) unless self == name
            else
              super
            end
          end

          # Throw an exception for invalid valus
          def raise_invalid(value)
            if value.is_a?(Numeric)
              raise EnumError, "#{value.inspect} is out of bounds of #{self.class.name}"
            else
              raise EnumError, "#{value.inspect} is not valid for #{self.class.name}"
            end
          end

          # Throw an exception for comparasion between different enums
          def raise_comparison(other)
            raise EnumError, "Comparison of #{self.class.name} with #{self.inspect} failed"
          end
      end
    end
  end
end
