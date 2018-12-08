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

            dangerous?(attribute.pluralize, true)
            dangerous?(attribute + '_text')

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
              klass.singleton_class.module_eval <<-STR, __FILE__, __LINE__ + 1
                def #{attribute.pluralize}                  # def statuses
                  ::#{subtype.klass.name}.values            #   ::Enum::Status.values
                end                                         # end
              STR
            end

            # Create the method that turn the attribute value into text using
            # the model scope
            def text
              klass.module_eval <<-STR, __FILE__, __LINE__ + 1
                def #{attribute}_text                       # def status_text
                  #{attribute}.text('#{attribute}', self)   #   status.text('status', self)
                end                                         # end
              STR
            end

            # Create all the methods that represent actions related to the
            # attribute value
            def all_values
              values_methods.each do |val, list|
                klass.module_eval <<-STR, __FILE__, __LINE__ + 1
                  scope :#{list[0]}, -> do                  # scope :disabled, -> do
                    where(#{attribute}: '#{val}')           #   where(status: 'disabled')
                  end                                       # end
                STR
                klass.module_eval <<-STR, __FILE__, __LINE__ + 1
                  def #{list[1]}                            # def disabled?
                    #{attribute}.#{val}?                    #   status.disabled?
                  end                                       # end

                  def #{list[2]}                            # def disabled!
                    if enum_save_on_bang                    #   if enum_save_on_bang
                      update!(#{attribute}: '#{val}')       #     update!(status: 'disabled')
                    else                                    #   else
                      #{attribute}.#{val}!                  #     status.disabled!
                    end                                     #   end
                  end                                       # end
                STR
              end
            end

        end
      end
    end
  end
end
