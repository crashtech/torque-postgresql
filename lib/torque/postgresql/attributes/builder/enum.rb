# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Attributes
      module Builder
        class Enum
          VALID_TYPES = %i[enum enum_set].freeze

          attr_accessor :klass, :attribute, :subtype, :options, :values,
            :klass_module, :instance_module

          # Start a new builder of methods for enum values on ActiveRecord::Base
          def initialize(klass, attribute, options)
            @klass     = klass
            @attribute = attribute.to_s
            @subtype   = klass.attribute_types[@attribute]
            @options   = options

            raise Interrupt unless subtype.respond_to?(:klass)
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
                key   = val.downcase.tr('- ', '__')
                scope = base % key
                ask   = scope + '?'
                bang  = scope + '!'
                [key, [scope, ask, bang, val]]
              end.to_h
            end
          end

          # Check if it's building the methods for sets
          def set_features?
            options[:set_features].present?
          end

          # Check if any of the methods that will be created get in conflict
          # with the base class methods
          def conflicting?
            return if options[:force] == true
            attributes = attribute.pluralize

            dangerous?(attributes, true)
            dangerous?("#{attributes}_keys", true)
            dangerous?("#{attributes}_texts", true)
            dangerous?("#{attributes}_options", true)
            dangerous?("#{attribute}_text")

            if set_features?
              dangerous?("has_#{attributes}", true)
              dangerous?("has_any_#{attributes}", true)
            end

            values_methods.each do |attr, (scope, ask, bang, *)|
              dangerous?(scope, true)
              dangerous?(bang)
              dangerous?(ask)
            end
          rescue Interrupt => err
            raise ArgumentError, <<-MSG.squish
              Enum #{subtype.name} was not able to generate requested
              methods because the method #{err} already exists in
              #{klass.name}.
            MSG
          end

          # Create all methods needed
          def build
            @klass_module = Module.new
            @instance_module = Module.new

            plural
            stringify
            all_values
            set_scopes if set_features?

            klass.extend klass_module
            klass.include instance_module
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
            rescue Interrupt => e
              raise e if Torque::PostgreSQL.config.enum.raise_conflicting
              type = class_method ? 'class method' : 'instance method'
              indicator = class_method ? '.' : '#'

              Torque::PostgreSQL.logger.info(<<~MSG.squish)
                Creating #{class_method} :#{method_name} for enum.
                Overwriting existing method #{klass.name}#{indicator}#{method_name}.
              MSG
            end

            # Create the method that allow access to the list of values
            def plural
              enum_klass = subtype.klass.name
              klass_module.module_eval <<-RUBY, __FILE__, __LINE__ + 1
                def #{attribute.pluralize}                                  # def roles
                  ::#{enum_klass}.values                                    #   Enum::Roles.values
                end                                                         # end

                def #{attribute.pluralize}_keys                             # def roles_keys
                  ::#{enum_klass}.keys                                      #   Enum::Roles.keys
                end                                                         # end

                def #{attribute.pluralize}_texts                            # def roles_texts
                  ::#{enum_klass}.members.map do |member|                   #   Enum::Roles.members do |member|
                    member.text('#{attribute}', self)                       #     member.text('role', self)
                  end                                                       #   end
                end                                                         # end

                def #{attribute.pluralize}_options                          # def roles_options
                  #{attribute.pluralize}_texts.zip(::#{enum_klass}.values)  #   roles_texts.zip(Enum::Roles.values)
                end                                                         # end
              RUBY
            end

            # Create additional methods when the enum is a set, which needs
            # better ways to check if values are present or not
            def set_scopes
              cast_type = subtype.name.chomp('[]')
              klass_module.module_eval <<-RUBY, __FILE__, __LINE__ + 1
                def has_#{attribute.pluralize}(*values)                             # def has_roles(*values)
                  attr = arel_table['#{attribute}']                                 #   attr = arel_table['role']
                  where(attr.contains(::Arel.array(values, cast: '#{cast_type}')))  #   where(attr.contains(::Arel.array(values, cast: 'roles')))
                end                                                                 # end

                def has_any_#{attribute.pluralize}(*values)                         # def has_roles(*values)
                  attr = arel_table['#{attribute}']                                 #   attr = arel_table['role']
                  where(attr.overlaps(::Arel.array(values, cast: '#{cast_type}')))  #   where(attr.overlaps(::Arel.array(values, cast: 'roles')))
                end                                                                 # end
              RUBY
            end

            # Create the method that turn the attribute value into text using
            # the model scope
            def stringify
              instance_module.module_eval <<-RUBY, __FILE__, __LINE__ + 1
                def #{attribute}_text                      # def role_text
                  #{attribute}.text('#{attribute}', self)  #   role.text('role', self)
                end                                        # end
              RUBY
            end

            # Create all the methods that represent actions related to the
            # attribute value
            def all_values
              klass_content = ''
              instance_content = ''
              enum_klass = subtype.klass.name

              values_methods.each do |key, (scope, ask, bang, val)|
                klass_content += <<-RUBY
                  def #{scope}                                    # def admin
                    attr = arel_table['#{attribute}']             #   attr = arel_table['role']
                    where(::#{enum_klass}.scope(attr, '#{val}'))  #   where(Enum::Roles.scope(attr, 'admin'))
                  end                                             # end
                RUBY

                instance_content += <<-RUBY
                  def #{ask}                                      # def admin?
                    #{attribute}.#{key}?                          #   role.admin?
                  end                                             # end

                  def #{bang}                                     # admin!
                    self.#{attribute} = '#{val}'                  #   self.role = 'admin'
                    return unless #{attribute}_changed?           #   return unless role_changed?
                    return save! if Torque::PostgreSQL.config.enum.save_on_bang
                    true                                          #   true
                  end                                             # end
                RUBY
              end

              klass_module.module_eval(klass_content)
              instance_module.module_eval(instance_content)
            end
        end
      end
    end
  end
end
