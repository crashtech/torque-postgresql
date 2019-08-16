module Torque
  module PostgreSQL
    module Attributes
      module Builder
        class Period
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

          attr_accessor :klass, :attribute, :options, :type, :arel_attribute, :default,
            :current_getter, :type_caster, :default_sql, :threshold, :dynamic_threshold,
            :period_module

          # Start a new builder of methods for period values on
          # ActiveRecord::Base
          def initialize(klass, attribute, _, options)
            @klass     = klass
            @attribute = attribute.to_s
            @options   = options
            @type      = klass.attribute_types[attribute].type

            @arel_attribute = klass.arel_table[attribute]
            @current_getter = CURRENT_GETTERS[type]
            @type_caster    = TYPE_CASTERS[type]

            @default = options[:pessimistic].blank?
            @default_sql = ::Arel.sql(@default.inspect.upcase)

            @threshold = options[:threshold].presence

            raise ArgumentError, <<-MSG.squish unless SUPPORTED_TYPES.include?(type)
              #{subtype.class.name} cannot be generated for #{attribute} because its type
              #{type} is not supported. Only #{SUPPORTED_TYPES.join(', ')} are supported.
            MSG
          end

          # Generate all the method names
          def method_names
            @method_names ||= options.fetch(:methods, {}).symbolize_keys
              .reverse_merge(default_method_names)
          end

          # Get the list of methods associated withe the class
          def klass_method_names
            @klass_method_names ||= method_names.to_a[0..12].to_h
          end

          # Get the list of methods associated withe the instances
          def instance_method_names
            @instance_method_names ||= method_names.to_a[13..19].to_h
          end

          # Check if any of the methods that will be created get in conflict
          # with the base class methods
          def conflicting?
            return false if options[:force] == true

            klass_method_names.values.each { |name| dangerous?(name, true) }
            instance_method_names.values.each { |name| dangerous?(name) }

            return false
          rescue Interrupt => err
            raise ArgumentError, <<-MSG.squish
              #{subtype.class.name} was not able to generate requested
              methods because the method #{err} already exists in
              #{klass.name}.
            MSG
          end

          # Create all methods needed
          def build
            @period_module = Module.new

            build_singleton_methods
            build_instance_methods

            klass.include period_module
          end

          # Create an arel named function
          def named_function(name, *args)
            ::Arel::Nodes::NamedFunction.new(name.to_s, args)
          end

          # Create an arel version of +nullif+ function
          def arel_nullif(*args)
            named_function('nullif', args)
          end

          # Create an arel version of +coalesce+ function
          def arel_coalesce(*args)
            named_function('coalesce', args)
          end

          # Create an arel version of an empty value for the range
          def arel_empty_value
            named_function(type, [::Arel.sql('NULL'), ::Arel.sql('NULL')])
          end

          # Get the main arel condition to check the value
          def arel_check_condition(type, value)
            value = ::Arel.sql(klass.connection.quote(value))

            checker = arel_nullif(arel_attribute, arel_empty_value)
            checker = checker.public_send(type, value.cast(type_caster))
            arel_coalesce(checker, default_sql)
          end

          private

            # Check how to provide the threshold value
            def threshold_value
              @threshold_value ||= begin
                case threshold
                when Symbol, String
                  klass.arel_table[threshold]
                when ActiveSupport::Duration
                  ::Arel.sql("#{threshold.to_i} seconds").cast(:interval)
                when Numeric
                  value = threshold.to_i.to_s
                  value << type_caster.eql?(:date) ? ' days' : ' seconds'
                  ::Arel.sql(value).cast(:interval)
                end
              end
            end

            # Generates the default method names
            def default_method_names
              Torque::PostgreSQL.config.period.method_names.transform_values do |value|
                format(value, attribute)
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

            # Build model methods
            def build_singleton_methods
              attr = attribute
              builder = self
              arel_attr = arel_attribute
              threshold_sql = threshold_value

              # TODO: Rewrite these as string
              klass.scope method_names[:current_on], ->(value) do
                where(builder.arel_check_condition(:contains, value))
              end

              klass.scope method_names[:current], -> do
                public_send(builder.method_names[:current_on], eval(builder.current_getter))
              end

              klass.scope method_names[:not_current], -> do
                current_value = eval(builder.current_getter)
                where.not(builder.arel_check_condition(:contains, current_value))
              end

              klass.scope method_names[:overlapping], ->(value) do
                value = arel_table[value] if value.is_a?(Symbol)
                where(arel_attr.overlaps(value))
              end

              klass.scope method_names[:not_overlapping], ->(value) do
                value = arel_table[value] if value.is_a?(Symbol)
                where.not(arel_attr.overlaps(value))
              end

              klass.scope method_names[:starting_after], ->(value) do
                where(builder.named_function(:lower, arel_attr).gt(value))
              end

              klass.scope method_names[:starting_before], ->(value) do
                where(builder.named_function(:lower, arel_attr).lt(value))
              end

              klass.scope method_names[:finishing_after], ->(value) do
                where(builder.named_function(:upper, arel_attr).gt(value))
              end

              klass.scope method_names[:finishing_before], ->(value) do
                where(builder.named_function(:upper, arel_attr).lt(value))
              end

              if threshold.present?
                klass.scope method_names[:real_starting_after], ->(value) do
                  condition = builder.named_function(:lower, arel_attr) + threshold_sql
                  where(condition.gt(value))
                end

                klass.scope method_names[:real_starting_before], ->(value) do
                  condition = builder.named_function(:lower, arel_attribute) + threshold_sql
                  where(condition.lt(value))
                end

                klass.scope method_names[:real_finishing_after], ->(value) do
                  condition = builder.named_function(:upper, arel_attribute) + threshold_sql
                  where(condition.gt(value))
                end

                klass.scope method_names[:real_finishing_before], ->(value) do
                  condition = builder.named_function(:upper, arel_attribute) + threshold_sql
                  where(condition.lt(value))
                end
              end
            end

            # Build model instance methods
            def build_instance_methods
              attr = attribute
              builder = self

              attr_threshold = threshold
              attr_threshold = attr_threshold.to_sym if attr_threshold.is_a?(String)
              attr_threshold = attr_threshold.seconds if attr_threshold.is_a?(Numeric)

              # TODO: Rewrite these as string
              period_module.module_eval do
                define_method(builder.method_names[:current?]) do
                  public_send(builder.method_names[:current_on?], eval(builder.current_getter))
                end

                define_method(builder.method_names[:current_on?]) do |value|
                  attr_value = public_send(attr)
                  return builder.default if attr_value.nil? ||
                    (attr_value.first.try(:infinite?) && attr_value.last.try(:infinite?))

                  attr_value.include?(value)
                end

                define_method(builder.method_names[:start]) do
                  public_send(attr)&.first
                end

                define_method(builder.method_names[:finish]) do
                  public_send(attr)&.last
                end

                if attr_threshold.present?
                  define_method(builder.method_names[:real]) do
                    left = public_send(builder.method_names[:real_start])
                    right = public_send(builder.method_names[:real_finish])
                    return unless left || right

                    left ||= -::Float::INFINITY
                    right ||= ::Float::INFINITY

                    left..right
                  end

                  define_method(builder.method_names[:real_start]) do
                    threshold = attr_threshold
                    threshold = public_send(threshold) if threshold.is_a?(Symbol)
                    public_send(attr)&.first.try(:-, threshold)
                  end

                  define_method(builder.method_names[:real_finish]) do
                    threshold = attr_threshold
                    threshold = public_send(threshold) if threshold.is_a?(Symbol)
                    public_send(attr)&.last.try(:+, threshold)
                  end
                end
              end
            end
        end
      end
    end
  end
end
