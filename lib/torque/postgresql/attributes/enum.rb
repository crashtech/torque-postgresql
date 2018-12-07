module Torque
  module PostgreSQL
    module Attributes
      class Enum < String
        include Comparable

        class EnumError < ArgumentError; end

        LAZY_VALUE = 0.chr

        class << self
          include Enumerable

          delegate :each, :sample, to: :members

          # Find or create the class that will handle the value
          def lookup(name)
            const     = name.to_s.camelize
            namespace = Torque::PostgreSQL.config.enum.namespace

            return namespace.const_get(const) if namespace.const_defined?(const)
            namespace.const_set(const, Class.new(Enum))
          end

          # Provide a method on the given class to setup which enums will be
          # manually initialized
          def include_on(klass)
            method_name = Torque::PostgreSQL.config.enum.base_method
            klass.singleton_class.class_eval <<-STR, __FILE__, __LINE__ + 1
              def #{method_name}(*args, **options)
                args.each do |attribute|
                  type = attribute_types[attribute.to_s]
                  TypeMap.lookup(type, self, attribute.to_s, false, options)
                end
              end
            STR
          end

          # You can specify the connection name for each enum
          def connection_specification_name
            return self == Enum ? 'primary' : superclass.connection_specification_name
          end

          # Overpass new so blank values return only nil
          def new(value)
            return Lazy.new(self, LAZY_VALUE) if value.blank?
            super
          end

          # Load the list of values in a lazy way
          def values
            @values ||= self == Enum ? nil : begin
              conn_name = connection_specification_name
              conn = connection(conn_name)
              conn.enum_values(type_name).freeze
            end
          end

          # Different from values, it returns the list of items already casted
          def members
            values.dup.map(&method(:new))
          end

          # Fetch a value from the list
          # see https://github.com/rails/rails/blob/v5.0.0/activerecord/lib/active_record/fixtures.rb#L656
          # see https://github.com/rails/rails/blob/v5.0.0/activerecord/lib/active_record/validations/uniqueness.rb#L101
          def fetch(value, *)
            return nil unless values.include?(value)
            send(value)
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

          private

            # Allows checking value existance
            def respond_to_missing?(method_name, include_private = false)
              valid?(method_name)
            end

            # Allow fast creation of values
            def method_missing(method_name, *arguments)
              return super if self == Enum
              valid?(method_name) ? new(method_name.to_s) : super
            end

            # Get a connection based on its name
            def connection(name)
              ActiveRecord::Base.connection_handler.retrieve_connection(name)
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
          nil? ? 'nil' : "#<#{self.class.name} #{super}>"
        end

        private

          # Get the i18n keys to check
          def i18n_keys(attr = nil, model = nil)
            values = { type: self.class.type_name, value: to_s }
            list_from = :i18n_type_scopes

            if attr && model
              values[:attr] = attr
              values[:model] = model.class.model_name.i18n_key
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
              self == name.tr('_', '-') || self == name
            elsif name.chomp!('!')
              replace(name)
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

      # Create the methods related to the attribute to handle the enum type
      TypeMap.register_type Adapter::OID::Enum do |subtype, attribute, initial = false, options = nil|
        break if initial && !Torque::PostgreSQL.config.enum.initializer
        options = {} if options.nil?

        # Generate methods on self class
        builder = Builder::Enum.new(self, attribute, subtype, initial, options)
        break if builder.conflicting?
        builder.build

        # Mark the enum as defined
        defined_enums[attribute] = subtype.klass
      end
    end
  end
end
