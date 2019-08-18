module Torque
  module PostgreSQL
    module Attributes
      module Builder
        # TODO: Allow methods to have nil in order to not include that specific method
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
            @type      = klass.attribute_types[@attribute].type

            @arel_attribute = klass.arel_table[@attribute]
            @current_getter = CURRENT_GETTERS[type]
            @type_caster    = TYPE_CASTERS[type]

            @default = options[:pessimistic].blank?
            @default_sql = ::Arel.sql(klass.connection.quote(@default))

            @threshold = options[:threshold].presence

            raise ArgumentError, <<-MSG.squish unless SUPPORTED_TYPES.include?(type)
              Period cannot be generated for #{attribute} because its type
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
            @klass_method_names ||= method_names.to_a[0..20].to_h
          end

          # Get the list of methods associated withe the instances
          def instance_method_names
            @instance_method_names ||= method_names.to_a[21..27].to_h
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

          # When the time has a threshold, then the real attribute is complex
          def real_arel_attribute
            return arel_attribute unless threshold.present?

            left = named_function(:lower, arel_attribute) - threshold_value
            right = named_function(:upper, arel_attribute) + threshold_value

            if type.eql?(:daterange)
              left = left.cast(:date)
              right = right.cast(:date)
            end

            @real_arel_attribute ||= named_function(type, left, right)
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

          # Create an arel version of the type with the following values
          def arel_convert_to_type(left, right = nil, set_type = nil)
            named_function(set_type || type, [left, right || left])
          end

          # Convert timestamp range to date range format
          def arel_daterange
            named_function(
              :daterange,
              named_function(:lower, real_arel_attribute).cast(:date),
              named_function(:upper, real_arel_attribute).cast(:date),
            )
          end

          # Create an arel version of an empty value for the range
          def arel_empty_value
            arel_convert_to_type(::Arel.sql('NULL'))
          end

          # Create an arel not condition
          def arel_not(value)
            named_function(:not, value)
          end

          # Get the main arel condition to check the value
          def arel_check_condition(type, value)
            value = ::Arel.sql(klass.connection.quote(value))

            checker = arel_nullif(real_arel_attribute, arel_empty_value)
            checker = checker.public_send(type, value.cast(type_caster))
            arel_coalesce(checker, default_sql)
          end

          # Check how to provide the threshold value
          def threshold_value
            @threshold_value ||= begin
              case threshold
              when Symbol, String
                klass.arel_table[threshold]
              when ActiveSupport::Duration
                ::Arel.sql("'#{threshold.to_i} seconds'").cast(:interval)
              when Numeric
                value = threshold.to_i.to_s
                value << type_caster.eql?(:date) ? ' days' : ' seconds'
                ::Arel.sql("'#{value}'").cast(:interval)
              end
            end
          end

          private

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

              klass.scope method_names[:containing], ->(value) do
                value = arel_table[value] if value.is_a?(Symbol)
                where(builder.arel_attribute.contains(value))
              end

              klass.scope method_names[:not_containing], ->(value) do
                value = arel_table[value] if value.is_a?(Symbol)
                where.not(builder.arel_attribute.contains(value))
              end

              klass.scope method_names[:overlapping], ->(value, right = nil) do
                value = arel_table[value] if value.is_a?(Symbol)

                if right.present?
                  value = ::Arel.sql(connection.quote(value))
                  right = ::Arel.sql(connection.quote(right))
                  value = builder.arel_convert_to_type(value, right)
                end

                where(builder.arel_attribute.overlaps(value))
              end

              klass.scope method_names[:not_overlapping], ->(value, right = nil) do
                value = arel_table[value] if value.is_a?(Symbol)

                if right.present?
                  value = ::Arel.sql(connection.quote(value))
                  right = ::Arel.sql(connection.quote(right))
                  value = builder.arel_convert_to_type(value, right)
                end

                where.not(builder.arel_attribute.overlaps(value))
              end

              klass.scope method_names[:starting_after], ->(value) do
                value = arel_table[value] if value.is_a?(Symbol)
                value = ::Arel.sql(connection.quote(value)) \
                  unless value.is_a?(::Arel::Attributes::Attribute)

                where(builder.named_function(:lower, builder.arel_attribute).gt(value))
              end

              klass.scope method_names[:starting_before], ->(value) do
                value = arel_table[value] if value.is_a?(Symbol)
                value = ::Arel.sql(connection.quote(value)) \
                  unless value.is_a?(::Arel::Attributes::Attribute)

                where(builder.named_function(:lower, builder.arel_attribute).lt(value))
              end

              klass.scope method_names[:finishing_after], ->(value) do
                value = arel_table[value] if value.is_a?(Symbol)
                value = ::Arel.sql(connection.quote(value)) \
                  unless value.is_a?(::Arel::Attributes::Attribute)

                where(builder.named_function(:upper, builder.arel_attribute).gt(value))
              end

              klass.scope method_names[:finishing_before], ->(value) do
                value = arel_table[value] if value.is_a?(Symbol)
                value = ::Arel.sql(connection.quote(value)) \
                  unless value.is_a?(::Arel::Attributes::Attribute)

                where(builder.named_function(:upper, builder.arel_attribute).lt(value))
              end

              if threshold.present?
                klass.scope method_names[:real_containing], ->(value) do
                  value = arel_table[value] if value.is_a?(Symbol)
                  where(builder.real_arel_attribute.contains(value))
                end

                klass.scope method_names[:real_overlapping], ->(value, right = nil) do
                  value = arel_table[value] if value.is_a?(Symbol)

                  if right.present?
                    value = ::Arel.sql(connection.quote(value))
                    right = ::Arel.sql(connection.quote(right))
                    value = builder.arel_convert_to_type(value, right)
                  end

                  where(builder.real_arel_attribute.overlaps(value))
                end

                klass.scope method_names[:real_starting_after], ->(value) do
                  value = arel_table[value] if value.is_a?(Symbol)
                  condition = builder.named_function(:lower, builder.arel_attribute)
                  condition -= builder.threshold_value
                  condition = condition.cast(:date) if builder.type.eql?(:daterange)
                  where(condition.gt(value))
                end

                klass.scope method_names[:real_starting_before], ->(value) do
                  value = arel_table[value] if value.is_a?(Symbol)
                  condition = builder.named_function(:lower, builder.arel_attribute)
                  condition -= builder.threshold_value
                  condition = condition.cast(:date) if builder.type.eql?(:daterange)
                  where(condition.lt(value))
                end

                klass.scope method_names[:real_finishing_after], ->(value) do
                  value = arel_table[value] if value.is_a?(Symbol)
                  condition = builder.named_function(:upper, builder.arel_attribute)
                  condition += builder.threshold_value
                  condition = condition.cast(:date) if builder.type.eql?(:daterange)
                  where(condition.gt(value))
                end

                klass.scope method_names[:real_finishing_before], ->(value) do
                  value = arel_table[value] if value.is_a?(Symbol)
                  condition = builder.named_function(:upper, builder.arel_attribute)
                  condition += builder.threshold_value
                  condition = condition.cast(:date) if builder.type.eql?(:daterange)
                  where(condition.lt(value))
                end
              end

              unless type.eql?(:daterange)
                klass.scope method_names[:containing_date], ->(value) do
                  value = arel_table[value] if value.is_a?(Symbol)
                  where(builder.arel_daterange.contains(value))
                end

                klass.scope method_names[:not_containing_date], ->(value) do
                  value = arel_table[value] if value.is_a?(Symbol)
                  where.not(builder.arel_daterange.contains(value))
                end

                klass.scope method_names[:overlapping_date], ->(value, right = nil) do
                  value = arel_table[value] if value.is_a?(Symbol)

                  if right.present?
                    value = ::Arel.sql(connection.quote(value))
                    right = ::Arel.sql(connection.quote(right))
                    value = builder.arel_convert_to_type(value, right, :daterange)
                  end

                  where(builder.arel_daterange.overlaps(value))
                end

                klass.scope method_names[:not_overlapping_date], ->(value, right = nil) do
                  value = arel_table[value] if value.is_a?(Symbol)

                  if right.present?
                    value = ::Arel.sql(connection.quote(value))
                    right = ::Arel.sql(connection.quote(right))
                    value = builder.arel_convert_to_type(value, right, :daterange)
                  end

                  where.not(builder.arel_daterange.overlaps(value))
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
                  attr_value = builder.threshold ? builder.method_names[:real] : attr
                  attr_value = public_send(attr_value)

                  return builder.default if attr_value.nil? ||
                    (attr_value.min.try(:infinite?) && attr_value.max.try(:infinite?))

                  attr_value.min < value && attr_value.max > value
                end

                define_method(builder.method_names[:start]) do
                  public_send(attr)&.min
                end

                define_method(builder.method_names[:finish]) do
                  public_send(attr)&.max
                end

                if attr_threshold.present?
                  define_method(builder.method_names[:start]) do
                    public_send(attr)&.min
                  end

                  define_method(builder.method_names[:finish]) do
                    public_send(attr)&.max
                  end

                  define_method(builder.method_names[:real]) do
                    left = public_send(builder.method_names[:real_start])
                    right = public_send(builder.method_names[:real_finish])
                    return unless left || right

                    left ||= -::Float::INFINITY
                    right ||= ::Float::INFINITY

                    (left..right)
                  end

                  define_method(builder.method_names[:real_start]) do
                    threshold = attr_threshold
                    threshold = public_send(threshold) if threshold.is_a?(Symbol)
                    result = public_send(attr)&.min.try(:-, threshold)
                    builder.type.eql?(:daterange) ? result&.to_date : result
                  end

                  define_method(builder.method_names[:real_finish]) do
                    threshold = attr_threshold
                    threshold = public_send(threshold) if threshold.is_a?(Symbol)
                    result = public_send(attr)&.max.try(:+, threshold)
                    builder.type.eql?(:daterange) ? result&.to_date : result
                  end
                end
              end
            end
        end
      end
    end
  end
end
