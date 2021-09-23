# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Attributes
      module Builder
        # TODO: Allow documenting by building the methods outside and importing
        # only the raw string
        class Period
          DIRECT_ACCESS_REGEX = /_?%s_?/
          SUPPORTED_TYPES = %i[daterange tsrange tstzrange].freeze
          CURRENT_GETTERS = {
            daterange: 'Date.today',
            tsrange:   'Time.zone.now',
            tstzrange: 'Time.zone.now',
          }.freeze

          TYPE_CASTERS = {
            daterange: :date,
            tsrange:   :timestamp,
            tstzrange: :timestamp,
          }.freeze

          attr_accessor :klass, :attribute, :options, :type, :default, :current_getter,
            :type_caster, :threshold, :dynamic_threshold, :klass_module, :instance_module

          # Start a new builder of methods for period values on
          # ActiveRecord::Base
          def initialize(klass, attribute, options)
            @klass     = klass
            @attribute = attribute.to_s
            @options   = options
            @type      = klass.attribute_types[@attribute].type

            raise ArgumentError, <<-MSG.squish unless SUPPORTED_TYPES.include?(type)
              Period cannot be generated for #{attribute} because its type
              #{type} is not supported. Only #{SUPPORTED_TYPES.join(', ')} are supported.
            MSG

            @current_getter = CURRENT_GETTERS[type]
            @type_caster    = TYPE_CASTERS[type]

            @default        = options[:pessimistic].blank?
          end

          # Check if can identify a threshold field
          def threshold
            @threshold ||= begin
              option = options[:threshold]
              return if option.eql?(false)

              unless option.eql?(true)
                return option.is_a?(String) ? option.to_sym : option
              end

              attributes = klass.attribute_names
              default_name = Torque::PostgreSQL.config.period.auto_threshold.to_s
              raise ArgumentError, <<-MSG.squish unless attributes.include?(default_name)
                Unable to find the #{default_name} to use as threshold for period
                features for #{attribute} in #{klass.name} model.
              MSG

              check_type = klass.attribute_types[default_name].type
              raise ArgumentError, <<-MSG.squish unless check_type.eql?(:interval)
                The #{default_name} has the wrong type to be used as threshold.
                Expected :interval got #{check_type.inspect} in #{klass.name} model.
              MSG

              default_name.to_sym
            end
          end

          # Generate all the method names
          def method_names
            @method_names ||= default_method_names.merge(options.fetch(:methods, {}))
          end

          # Get the list of methods associated withe the class
          def klass_method_names
            @klass_method_names ||= method_names.to_a[0..22].to_h
          end

          # Get the list of methods associated withe the instances
          def instance_method_names
            @instance_method_names ||= method_names.to_a[23..29].to_h
          end

          # Check if any of the methods that will be created get in conflict
          # with the base class methods
          def conflicting?
            return if options[:force] == true

            klass_method_names.values.each { |name| dangerous?(name, true) }
            instance_method_names.values.each { |name| dangerous?(name) }
          rescue Interrupt => err
            raise ArgumentError, <<-MSG.squish
              #{subtype.class.name} was not able to generate requested
              methods because the method #{err} already exists in
              #{klass.name}.
            MSG
          end

          # Create all methods needed
          def build
            @klass_module = Module.new
            @instance_module = Module.new

            value_args      = ['value']
            left_right_args = ['left', 'right = nil']

            ## Klass methods
            build_method_helper :klass, :current_on,                 value_args            # 00
            build_method_helper :klass, :current                                           # 01
            build_method_helper :klass, :not_current                                       # 02
            build_method_helper :klass, :containing,                 value_args            # 03
            build_method_helper :klass, :not_containing,             value_args            # 04
            build_method_helper :klass, :overlapping,                left_right_args       # 05
            build_method_helper :klass, :not_overlapping,            left_right_args       # 06
            build_method_helper :klass, :starting_after,             value_args            # 07
            build_method_helper :klass, :starting_before,            value_args            # 08
            build_method_helper :klass, :finishing_after,            value_args            # 09
            build_method_helper :klass, :finishing_before,           value_args            # 10

            if threshold.present?
              build_method_helper :klass, :real_containing,          value_args            # 11
              build_method_helper :klass, :real_overlapping,         left_right_args       # 12
              build_method_helper :klass, :real_starting_after,      value_args            # 13
              build_method_helper :klass, :real_starting_before,     value_args            # 14
              build_method_helper :klass, :real_finishing_after,     value_args            # 15
              build_method_helper :klass, :real_finishing_before,    value_args            # 16
            end

            unless type.eql?(:daterange)
              build_method_helper :klass, :containing_date,          value_args            # 17
              build_method_helper :klass, :not_containing_date,      value_args            # 18
              build_method_helper :klass, :overlapping_date,         left_right_args       # 19
              build_method_helper :klass, :not_overlapping_date,     left_right_args       # 20

              if threshold.present?
                build_method_helper :klass, :real_containing_date,   value_args            # 21
                build_method_helper :klass, :real_overlapping_date,  left_right_args       # 22
              end
            end

            ## Instance methods
            build_method_helper :instance, :current?                                       # 23
            build_method_helper :instance, :current_on?,             value_args            # 24
            build_method_helper :instance, :start                                          # 25
            build_method_helper :instance, :finish                                         # 26

            if threshold.present?
              build_method_helper :instance, :real                                         # 27
              build_method_helper :instance, :real_start                                   # 28
              build_method_helper :instance, :real_finish                                  # 29
            end

            klass.extend klass_module
            klass.include instance_module
          end

          def build_method_helper(type, key, args = [])
            method_name = method_names[key]
            return if method_name.nil?

            method_content = send("#{type}_#{key}")
            method_content = define_string_method(method_name, method_content, args)

            source_module = send("#{type}_module")
            source_module.module_eval(method_content)
          end

          private

            # Generates the default method names
            def default_method_names
              list = Torque::PostgreSQL.config.period.method_names.dup

              if options.fetch(:prefixed, true)
                list.transform_values { |value| format(value, attribute) }
              else
                list = list.merge(Torque::PostgreSQL.config.period.direct_method_names)
                list.transform_values { |value| value.gsub(DIRECT_ACCESS_REGEX, '') }
              end
            end

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

            ## BUILDER HELPERS
            def define_string_method(name, body, args = [])
              headline = "def #{name}"
              headline += "(#{args.join(', ')})"
              [headline, body, 'end'].join("\n")
            end

            def arel_attribute
              @arel_attribute ||= "arel_table[#{attribute.inspect}]"
            end

            def arel_default_sql
              @arel_default_sql ||= arel_sql_quote(@default.inspect)
            end

            def arel_sql_quote(value)
              "::Arel.sql(connection.quote(#{value}))"
            end

            # Check how to provide the threshold value
            def arel_threshold_value
              @arel_threshold_value ||= begin
                case threshold
                when Symbol, String
                  "arel_attribute('#{threshold}')"
                when ActiveSupport::Duration
                  value = "'#{threshold.to_i} seconds'"
                  "::Arel.sql(\"#{value}\").cast(:interval)"
                when Numeric
                  value = threshold.to_i.to_s
                  value << type_caster.eql?(:date) ? ' days' : ' seconds'
                  value = "'#{value}'"
                  "::Arel.sql(\"#{value}\").cast(:interval)"
                end
              end
            end

            # Start at version of the value
            def arel_start_at
              @arel_start_at ||= arel_named_function('lower', arel_attribute)
            end

            # Finish at version of the value
            def arel_finish_at
              @arel_finish_at ||= arel_named_function('upper', arel_attribute)
            end

            # Start at version of the value with threshold
            def arel_real_start_at
              return arel_start_at unless threshold.present?
              @arel_real_start_at ||= begin
                result = +"(#{arel_start_at} - #{arel_threshold_value})"
                result << '.cast(:date)' if  type.eql?(:daterange)
                result
              end
            end

            # Finish at version of the value with threshold
            def arel_real_finish_at
              return arel_finish_at unless threshold.present?
              @arel_real_finish_at ||= begin
                result = +"(#{arel_finish_at} + #{arel_threshold_value})"
                result << '.cast(:date)' if  type.eql?(:daterange)
                result
              end
            end

            # When the time has a threshold, then the real attribute is complex
            def arel_real_attribute
              return arel_attribute unless threshold.present?
              @arel_real_attribute ||= arel_named_function(
                type, arel_real_start_at, arel_real_finish_at,
              )
            end

            # Create an arel version of the type with the following values
            def arel_convert_to_type(left, right = nil, set_type = nil)
              arel_named_function(set_type || type, left, right || left)
            end

            # Create an arel named function
            def arel_named_function(name, *args)
              result = +"::Arel::Nodes::NamedFunction.new(#{name.to_s.inspect}"
              result << ', [' << args.join(', ') << ']' if args.present?
              result << ')'
            end

            # Create an arel version of +nullif+ function
            def arel_nullif(*args)
              arel_named_function('nullif', *args)
            end

            # Create an arel version of +coalesce+ function
            def arel_coalesce(*args)
              arel_named_function('coalesce', *args)
            end

            # Create an arel version of an empty value for the range
            def arel_empty_value
              arel_convert_to_type('::Arel.sql(\'NULL\')')
            end

            # Convert timestamp range to date range format
            def arel_daterange(real = false)
              arel_named_function(
                'daterange',
                (real ? arel_real_start_at : arel_start_at) + '.cast(:date)',
                (real ? arel_real_finish_at : arel_finish_at) + '.cast(:date)',
                '::Arel.sql("\'[]\'")',
              )
            end

            def arel_check_condition(type)
              checker = arel_nullif(arel_real_attribute, arel_empty_value)
              checker << ".#{type}(value.cast(#{type_caster.inspect}))"
              arel_coalesce(checker, arel_default_sql)
            end

            def arel_formatting_value(condition = nil, value = 'value', cast: nil)
              [
                "#{value} = arel_table[#{value}] if #{value}.is_a?(Symbol)",
                "unless #{value}.respond_to?(:cast)",
                "  #{value} = ::Arel.sql(connection.quote(#{value}))",
                ("  #{value} = #{value}.cast(#{cast.inspect})" if cast),
                'end',
                condition,
              ].compact.join("\n")
            end

            def arel_formatting_left_right(condition, set_type = nil, cast: nil)
              [
                arel_formatting_value(nil, 'left', cast: cast),
                '',
                'if right.present?',
                '  ' + arel_formatting_value(nil, 'right', cast: cast),
                "  value = #{arel_convert_to_type('left', 'right', set_type)}",
                'else',
                '  value = left',
                'end',
                '',
                condition,
              ].join("\n")
            end

            ## METHOD BUILDERS
            def klass_current_on
              arel_formatting_value("where(#{arel_check_condition(:contains)})")
            end

            def klass_current
              [
                "value = #{arel_sql_quote(current_getter)}",
                "where(#{arel_check_condition(:contains)})",
              ].join("\n")
            end

            def klass_not_current
              [
                "value = #{arel_sql_quote(current_getter)}",
                "where.not(#{arel_check_condition(:contains)})",
              ].join("\n")
            end

            def klass_containing
              arel_formatting_value("where(#{arel_attribute}.contains(value))")
            end

            def klass_not_containing
              arel_formatting_value("where.not(#{arel_attribute}.contains(value))")
            end

            def klass_overlapping
              arel_formatting_left_right("where(#{arel_attribute}.overlaps(value))")
            end

            def klass_not_overlapping
              arel_formatting_left_right("where.not(#{arel_attribute}.overlaps(value))")
            end

            def klass_starting_after
              arel_formatting_value("where((#{arel_start_at}).gt(value))")
            end

            def klass_starting_before
              arel_formatting_value("where((#{arel_start_at}).lt(value))")
            end

            def klass_finishing_after
              arel_formatting_value("where((#{arel_finish_at}).gt(value))")
            end

            def klass_finishing_before
              arel_formatting_value("where((#{arel_finish_at}).lt(value))")
            end

            def klass_real_containing
              arel_formatting_value("where(#{arel_real_attribute}.contains(value))")
            end

            def klass_real_overlapping
              arel_formatting_left_right("where(#{arel_real_attribute}.overlaps(value))")
            end

            def klass_real_starting_after
              arel_formatting_value("where(#{arel_real_start_at}.gt(value))")
            end

            def klass_real_starting_before
              arel_formatting_value("where(#{arel_real_start_at}.lt(value))")
            end

            def klass_real_finishing_after
              arel_formatting_value("where(#{arel_real_finish_at}.gt(value))")
            end

            def klass_real_finishing_before
              arel_formatting_value("where(#{arel_real_finish_at}.lt(value))")
            end

            def klass_containing_date
              arel_formatting_value("where(#{arel_daterange}.contains(value))",
                cast: :date)
            end

            def klass_not_containing_date
              arel_formatting_value("where.not(#{arel_daterange}.contains(value))",
                cast: :date)
            end

            def klass_overlapping_date
              arel_formatting_left_right("where(#{arel_daterange}.overlaps(value))",
                :daterange, cast: :date)
            end

            def klass_not_overlapping_date
              arel_formatting_left_right("where.not(#{arel_daterange}.overlaps(value))",
                :daterange, cast: :date)
            end

            def klass_real_containing_date
              arel_formatting_value("where(#{arel_daterange(true)}.contains(value))",
                cast: :date)
            end

            def klass_real_overlapping_date
              arel_formatting_left_right("where(#{arel_daterange(true)}.overlaps(value))",
                :daterange, cast: :date)
            end

            def instance_current?
              "#{method_names[:current_on?]}(#{current_getter})"
            end

            def instance_current_on?
              attr_value = threshold.present? ? method_names[:real] : attribute
              default_value = default.inspect

              "#{attr_value}.nil? ? #{default_value} : #{attr_value}.include?(value)"
            end

            def instance_start
              "#{attribute}&.min"
            end

            def instance_finish
              "#{attribute}&.max"
            end

            def instance_real
              left = method_names[:real_start]
              right = method_names[:real_finish]

              [
                "left = #{left}",
                "right = #{right}",
                'return unless left || right',
                '((left || -::Float::INFINITY)..(right || ::Float::INFINITY))',
              ].join("\n")
            end

            def instance_real_start
              suffix = type.eql?(:daterange) ? '.to_date' : ''
              threshold_value = threshold.is_a?(Symbol) \
                ? threshold.to_s \
                : threshold.to_i.to_s + '.seconds'

              [
                "return if #{method_names[:start]}.nil?",
                "value = #{method_names[:start]}",
                "value -= (#{threshold_value} || 0)",
                "value#{suffix}"
              ].join("\n")
            end

            def instance_real_finish
              suffix = type.eql?(:daterange) ? '.to_date' : ''
              threshold_value = threshold.is_a?(Symbol) \
                ? threshold.to_s \
                : threshold.to_i.to_s + '.seconds'

              [
                "return if #{method_names[:finish]}.nil?",
                "value = #{method_names[:finish]}",
                "value += (#{threshold_value} || 0)",
                "value#{suffix}"
              ].join("\n")
            end
        end
      end
    end
  end
end
