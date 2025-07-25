# frozen_string_literal: true

module Torque
  module PostgreSQL
    include ActiveSupport::Configurable

    # Use the same logger as the Active Record one
    def self.logger
      ActiveRecord::Base.logger
    end

    # Allow nested configurations
    # :TODO: Rely on +inheritable_copy+ to make nested configurations
    config.define_singleton_method(:nested) do |name, &block|
      klass = Class.new(ActiveSupport::Configurable::Configuration).new
      block.call(klass) if block
      send("#{name}=", klass)
    end

    # Set if any information that requires querying and searching or collecting
    # information should be eager loaded. This automatically changes when rails
    # same configuration is set to true
    config.eager_load = false

    # Set a list of irregular model name when associated with table names
    config.irregular_models = {}
    def config.irregular_models=(hash)
      PostgreSQL.config[:irregular_models] = hash.map do |(table, model)|
        [table.to_s, model.to_s]
      end.to_h
    end

    # Configure associations features
    config.nested(:associations) do |assoc|

      # Define if +belongs_to_many+ associations are marked as required by
      # default. False means that no validation will be performed
      assoc.belongs_to_many_required_by_default = false

    end

    # Configure multiple schemas
    config.nested(:schemas) do |schemas|

      # Enables schemas handler by this gem, not Rails's own implementation
      schemas.enabled = true

      # Defines a list of LIKE-based schemas to not consider for a multiple
      # schema database
      schemas.blacklist = %w[information_schema pg_%]

      # Defines a list of LIKE-based schemas to consider for a multiple schema
      # database
      schemas.whitelist = %w[public]

    end

    # Configure auxiliary statement features
    config.nested(:auxiliary_statement) do |cte|

      # Enables auxiliary statements handler by this gem, not Rails's own
      # implementation
      cte.enabled = true

      # Define the key that is used on auxiliary statements to send extra
      # arguments to format string or send on a proc
      cte.send_arguments_key = :args

      # Estipulate a class name (which may contain namespace) that exposes the
      # auxiliary statement in order to perform detached CTEs
      cte.exposed_class = 'TorqueCTE'

      # Estipulate a class name (which may contain namespace) that exposes the
      # recursive auxiliary statement in order to perform detached CTEs
      cte.exposed_recursive_class = 'TorqueRecursiveCTE'

    end

    # Configure ENUM features
    config.nested(:enum) do |enum|

      # Enables enum handler by this gem, not Rails's own implementation
      enum.enabled = true

      # The name of the method to be used on any ActiveRecord::Base to
      # initialize model-based enum features
      enum.base_method = :torque_enum

      # The name of the method to be used on any ActiveRecord::Base to
      # initialize model-based enum set features
      enum.set_method = :torque_enum_set

      # Indicates if bang methods like 'disabled!' should update the record on
      # database or not
      enum.save_on_bang = true

      # Indicates if it should raise errors when a generated method would
      # conflict with an existing one
      enum.raise_conflicting = false

      # Specify the namespace of each enum type of value
      enum.namespace = nil

      # Specify the scopes for I18n translations
      enum.i18n_scopes = [
        'activerecord.attributes.%{model}.%{attr}.%{value}',
        'activerecord.attributes.%{attr}.%{value}',
        'activerecord.enums.%{type}.%{value}',
        'enum.%{type}.%{value}',
        'enum.%{value}'
      ]

      # Specify the scopes for I18n translations but with type only
      enum.i18n_type_scopes = Enumerator.new do |yielder|
        enum.i18n_scopes.each do |key|
          next if key.include?('%{model}') || key.include?('%{attr}')
          yielder << key
        end
      end

    end

    # Configure geometry data types
    config.nested(:geometry) do |geometry|

      # Enables geometry handler by this gem, not Rails's own implementation
      geometry.enabled = true

      # Define the class that will be handling Point data types after decoding
      # it. Any class provided here must respond to 'x', and 'y'
      geometry.point_class = ActiveRecord::Point

      # Define the class that will be handling Box data types after decoding it.
      # Any class provided here must respond to 'x1', 'y1', 'x2', and 'y2'
      geometry.box_class = nil

      # Define the class that will be handling Circle data types after decoding
      # it. Any class provided here must respond to 'x', 'y', and 'r'
      geometry.circle_class = nil

      # Define the class that will be handling Line data types after decoding
      # it. Any class provided here must respond to 'a', 'b', and 'c'
      geometry.line_class = nil

      # Define the class that will be handling Segment data types after decoding
      # it. Any class provided here must respond to 'x1', 'y1', 'x2', and 'y2'
      geometry.segment_class = nil

    end

    # Configure inheritance features
    config.nested(:inheritance) do |inheritance|

      # Define the lookup of models from their given name to be inverted, which
      # means that they are going to be form the last namespaced one to the
      # most namespaced one
      inheritance.inverse_lookup = true

      # Determines the name of the column used to collect the table of each
      # record. When the table has inheritance tables, this column will return
      # the name of the table that actually holds the record
      inheritance.record_class_column_name = :_record_class

      # Determines the name of the column used when identifying that the loaded
      # records should be casted to its correctly model. This will be TRUE for
      # the records mentioned on `cast_records`
      inheritance.auto_cast_column_name = :_auto_cast

    end

    # Configure period features
    config.nested(:period) do |period|

      # Enables period handler by this gem
      period.enabled = true

      # The name of the method to be used on any ActiveRecord::Base to
      # initialize model-based period features
      period.base_method = :period_for

      # The default name for a threshold attribute, which will automatically
      # enable threshold features
      period.auto_threshold = :threshold

      # Define the list of methods that will be created by default while setting
      # up a new period field
      period.method_names = {
        current_on:            '%s_on',                       # 00
        current:               'current_%s',                  # 01
        not_current:           'not_current_%s',              # 02
        containing:            '%s_containing',               # 03
        not_containing:        '%s_not_containing',           # 04
        overlapping:           '%s_overlapping',              # 05
        not_overlapping:       '%s_not_overlapping',          # 06
        starting_after:        '%s_starting_after',           # 07
        starting_before:       '%s_starting_before',          # 08
        finishing_after:       '%s_finishing_after',          # 09
        finishing_before:      '%s_finishing_before',         # 10

        real_containing:       '%s_real_containing',          # 11
        real_overlapping:      '%s_real_overlapping',         # 12
        real_starting_after:   '%s_real_starting_after',      # 13
        real_starting_before:  '%s_real_starting_before',     # 14
        real_finishing_after:  '%s_real_finishing_after',     # 15
        real_finishing_before: '%s_real_finishing_before',    # 16

        containing_date:       '%s_containing_date',          # 17
        not_containing_date:   '%s_not_containing_date',      # 18
        overlapping_date:      '%s_overlapping_date',         # 19
        not_overlapping_date:  '%s_not_overlapping_date',     # 20
        real_containing_date:  '%s_real_containing_date',     # 21
        real_overlapping_date: '%s_real_overlapping_date',    # 22

        current?:              'current_%s?',                 # 23
        current_on?:           'current_%s_on?',              # 24
        start:                 '%s_start',                    # 25
        finish:                '%s_finish',                   # 26
        real:                  'real_%s',                     # 27
        real_start:            '%s_real_start',               # 28
        real_finish:           '%s_real_finish',              # 29
      }

      # If the period is marked as direct access, without the field name,
      # then these method names will replace the default ones
      period.direct_method_names = {
        current_on:          'happening_in',
        containing:          'during',
        not_containing:      'not_during',
        real_containing:     'real_during',

        containing_date:     'during_date',
        not_containing_date: 'not_during_date',

        current_on?:         'happening_in?',
        start:               'start_at',
        finish:              'finish_at',
        real:                'real_time',
        real_start:          'real_start_at',
        real_finish:         'real_finish_at',
      }

    end

    # Configure period features
    config.nested(:interval) do |interval|

      # Enables interval handler by this gem, not Rails's own implementation
      interval.enabled = true

    end

    # Configure arel additional features
    config.nested(:arel) do |arel|

      # List of Arel INFIX operators that will be made available for using as
      # methods on Arel::Nodes::Node and Arel::Attribute
      arel.infix_operators = {
        'contained_by'        => '<@',
        'has_key'             => '?',
        'has_all_keys'        => '?&',
        'has_any_keys'        => '?|',
        'strictly_left'       => '<<',
        'strictly_right'      => '>>',
        'doesnt_right_extend' => '&<',
        'doesnt_left_extend'  => '&>',
        'adjacent_to'         => '-|-',
      }

    end

    # Configure full text search features
    config.nested(:full_text_search) do |fts|

      # Enables full text search handler by this gem
      fts.enabled = true

      # The name of the method to be used on any ActiveRecord::Base to
      # initialize model-based full text search features
      fts.base_method = :torque_search_for

      # Defines the default language when generating search vector columns
      fts.default_language = 'english'

      # Defines the default index type to be used when creating search vector.
      # It still requires that the column requests an index
      fts.default_index_type = :gin

    end

    # Configure predicate builder additional features
    config.nested(:predicate_builder) do |builder|

      # List which handlers are enabled by default
      builder.enabled = %i[regexp arel_attribute enumerator_lazy]

      # When active, values provided to array attributes will be handled more
      # efficiently. It will use the +ANY+ operator on a equality check and
      # overlaps when the given value is an array
      builder.handle_array_attributes = false

      # Make sure that the predicate builder will not spend more than 20ms
      # trying to produce the underlying array
      builder.lazy_timeout = 0.02

      # Since lazy array is uncommon, it is better to limit the number of
      # entries we try to pull so we don't cause a timeout or a long wait
      # iteration
      builder.lazy_limit = 2_000

    end

  end
end
