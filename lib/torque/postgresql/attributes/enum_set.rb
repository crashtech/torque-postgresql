module Torque
  module PostgreSQL
    module Attributes
      class EnumSet < Set
        include Comparable

        class EnumSetError < Enum::EnumError; end

        class << self
          include Enumerable

          delegate :each, to: :members
          delegate :values, :members, :texts, :to_options, :valid?, :size,
            :length, :connection_specification_name, to: :enum_source

          # Find or create the class that will handle the value
          def lookup(name, enum_klass)
            const     = name.to_s.camelize + 'Set'
            namespace = Torque::PostgreSQL.config.enum.namespace

            return namespace.const_get(const) if namespace.const_defined?(const)

            klass = Class.new(EnumSet)
            klass.const_set('EnumSource', enum_klass)
            namespace.const_set(const, klass)
          end

          # Provide a method on the given class to setup which enum sets will be
          # manually initialized
          def include_on(klass, method_name = nil)
            Enum.include_on(klass, method_name || Torque::PostgreSQL.config.enum.set_method)
          end

          # The original Enum implementation, for individual values
          def enum_source
            const_get('EnumSource')
          end

          # Use the power to get a sample of the value
          def sample
            new(rand(0..((2 ** size) - 1)))
          end

          # Overpass new so blank values return only nil
          def new(*values)
            return Lazy.new(self, []) if values.compact.blank?
            super
          end

          # Get the type name from its class name
          def type_name
            @type_name ||= enum_source.type_name + '[]'
          end

          # Fetch a value from the list
          # see https://github.com/rails/rails/blob/v5.0.0/activerecord/lib/active_record/fixtures.rb#L656
          # see https://github.com/rails/rails/blob/v5.0.0/activerecord/lib/active_record/validations/uniqueness.rb#L101
          def fetch(value, *)
            new(value.to_s) if values.include?(value)
          end
          alias [] fetch

          # Get the power, 2 ** index, of each element
          def power(*values)
            values.flatten.map do |item|
              item = item.to_i if item.is_a?(Enum)
              item = values.index(item) unless item.is_a?(Numeric)

              next 0 if item.nil? || item >= size
              2 ** item
            end.reduce(:+)
          end

          # Build an active record scope for a given atribute agains a value
          def scope(attribute, value)
            attribute.contains(Array.wrap(value))
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
        end

        # Override string initializer to check for a valid value
        def initialize(*values)
          items =
            if values.size === 1 && values.first.is_a?(Numeric)
              transform_power(values.first)
            else
              transform_values(values)
            end

          @hash = items.zip(Array.new(items.size, true)).to_h
        end

        # Allow comparison between values of the same enum
        def <=>(other)
          raise_comparison(other) if other.is_a?(EnumSet) && other.class != self.class

          to_i <=>
            case other
            when Numeric, EnumSet then other.to_i
            when String, Symbol   then self.class.power(other.to_s)
            when Array, Set       then self.class.power(*other)
            else raise_comparison(other)
            end
        end

        # Only allow value comparison with values of the same class
        def ==(other)
          (self <=> other) == 0
        rescue EnumSetError
          false
        end
        alias eql? ==

        # It only accepts if the other value is valid
        def replace(*values)
          super(transform_values(values))
        end

        # Get a translated version of the value
        def text(attr = nil, model = nil)
          map { |item| item.text(attr, model) }.to_sentence
        end
        alias to_s text

        # Get the index of the value
        def to_i
          self.class.power(@hash.keys)
        end

        # Change the inspection to show the enum name
        def inspect
          "[#{map(&:inspect).join(',')}]"
        end

        # Replace the setter by instantiating the value
        def []=(key, value)
          super(key, instantiate(value))
        end

        # Override the merge method to ensure formatted values
        def merge(other)
          super other.map(&method(:instantiate))
        end

        # Override bitwise & operator to ensure formatted values
        def &(other)
          other = other.entries.map(&method(:instantiate))
          values = @hash.keys.select { |k| other.include?(k) }
          self.class.new(values)
        end

        # Operations that requries the other values to be transformed as well
        %i[add delete include? subtract].each do |method_name|
          define_method(method_name) do |other|
            other =
              if other.is_a?(self.class)
                other
              elsif other.is_a?(::Enumerable)
                other.map(&method(:instantiate))
              else
                instantiate(other)
              end

            super(other)
          end
        end

        private

          # Create a new enum instance of the value
          def instantiate(value)
            value.is_a?(self.class.enum_source) ? value : self.class.enum_source.new(value)
          end

          # Turn a binary (power) definition into real values
          def transform_power(value)
            list = value.to_s(2).reverse.chars.map.with_index do |item, idx|
              next idx if item.eql?('1')
            end

            raise raise_invalid(value) if list.size > self.class.size
            self.class.members.values_at(*list.compact)
          end

          # Turn all the values into their respective Enum representations
          def transform_values(values)
            values = values.first if values.size.eql?(1) && values.first.is_a?(::Enumerable)
            values.map(&method(:instantiate)).reject(&:nil?)
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
              include?(name)
            elsif name.chomp!('!')
              add(name) unless include?(name)
            else
              super
            end
          end

          # Throw an exception for invalid valus
          def raise_invalid(value)
            if value.is_a?(Numeric)
              raise EnumSetError, "#{value.inspect} is out of bounds of #{self.class.name}"
            else
              raise EnumSetError, "#{value.inspect} is not valid for #{self.class.name}"
            end
          end

          # Throw an exception for comparasion between different enums
          def raise_comparison(other)
            raise EnumSetError, "Comparison of #{self.class.name} with #{self.inspect} failed"
          end
      end
    end
  end
end
