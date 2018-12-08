module Torque
  module PostgreSQL
    module Attributes
      module Builder
        class Enum

          attr_accessor :klass, :attribute, :subtype, :options, :values

          # Start a new builder of methods for composite values on
          # ActiveRecord::Base
          def initialize(klass, attribute, subtype, options)
            @klass     = klass
            @attribute = attribute.to_s
            @subtype   = subtype
            @options   = options

            @values    = subtype.klass.values

            if @options[:only]
              @values &= Array(@options[:only]).map(&:to_s)
            end

            if @options[:except]
              @values -= Array(@options[:except]).map(&:to_s)
            end
          end

          # Get the list of methods based on enum values
          def values_methods
            return @values_methods if defined?(@values_methods)

            prefix = options.fetch(:prefix, nil).try(:<<, '_')
            suffix = options.fetch(:suffix, nil).try(:prepend, '_')

            prefix = attribute + '_' if prefix == true
            suffix = '_' + attribute if suffix == true

            base   = "#{prefix}%s#{suffix}"

            @values_methods = begin
              values.map do |val|
                val   = val.tr('-', '_')
                scope = base % val
                ask   = scope + '?'
                bang  = scope + '!'
                [val, [scope, ask, bang]]
              end.to_h
            end
          end

          # Check if any of the methods that will be created get in conflict
          # with the base class methods
          def conflicting?
            return false if options[:force] == true
            attributes = attribute.pluralize

            dangerous?(attributes, true)
            dangerous?("#{attributes}_options", true)
            dangerous?("#{attributes}_texts", true)
            dangerous?("#{attribute}_text")

            values_methods.each do |attr, list|
              list.map(&method(:dangerous?))
            end

            return false
          rescue Interrupt => err
            raise ArgumentError, <<-MSG.strip.gsub(/\n +/, ' ')
              #{subtype.class.name} was not able to generate requested
              methods because the method #{err} already exists in
              #{klass.name}.
            MSG
          end

          # Create all methods needed
          def build
            plural
            text
            all_values
          end

          private

            # Check if the method already exists in the reference class
            def dangerous?(method_name, class_method = false)
              if class_method
                if klass.dangerous_class_method?(method_name)
                  raise Interrupt, method_name.to_s
                end
              else
                if klass.dangerous_attribute_method?(method_name)
                  raise Interrupt, method_name.to_s
                end
              end
            end

            # Create the method that allow access to the list of values
            def plural
              attr = attribute
              enum_klass = subtype.klass
              klass.singleton_class.module_eval do
                # def self.statuses() statuses end
                define_method(attr.pluralize) do
                  enum_klass.values
                end

                # def self.statuses_texts() members.map(&:text) end
                define_method(attr.pluralize + '_texts') do
                  enum_klass.members.map do |member|
                    member.text(attr, self)
                  end
                end

                # def self.statuses_options() statuses_texts.zip(statuses) end
                define_method(attr.pluralize + '_options') do
                  enum_klass.values
                end
              end
            end

            # Create the method that turn the attribute value into text using
            # the model scope
            def text
              attr = attribute
              klass.module_eval do
                # def status_text() status.text('status', self) end
                define_method("#{attr}_text") { send(attr).text(attr, self) }
              end
            end

            # Create all the methods that represent actions related to the
            # attribute value
            def all_values
              attr = attribute
              vals = values_methods
              klass.module_eval do
                vals.each do |val, list|
                  # scope :disabled, -> { where(status: 'disabled') }
                  scope list[0], -> { where(attr => val) }

                  # def disabled? status.disabled? end
                  define_method(list[1]) { send(attr).public_send("#{val}?") }

                  # def disabled! enum_save_on_bang ? update!(status: 'disabled') : status.disabled! end
                  define_method(list[2]) do
                    if enum_save_on_bang
                      update!(attr => val)
                    else
                      send(attr).public_send("#{val}!")
                    end
                  end
                end
              end
            end

        end
      end
    end
  end
end
