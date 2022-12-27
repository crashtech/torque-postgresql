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

    # Set if any information that requires querying and searching or collectiong
    # information shuld be eager loaded. This automatically changes when rails
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

      # Defines a list of LIKE-based schemas to not consider for a multiple
      # schema database
      schemas.blacklist = %w[information_schema pg_%]

      # Defines a list of LIKE-based schemas to consider for a multiple schema
      # database
      schemas.whitelist = %w[public]

    end

    # Configure auxiliary statement features
    config.nested(:auxiliary_statement) do |cte|

      # Define the key that is used on auxiliary statements to send extra
      # arguments to format string or send on a proc
      cte.send_arguments_key = :args

      # Estipulate a class name (which may contain namespace) that expose the
      # auxiliary statement in order to perform detached CTEs
      cte.exposed_class = 'TorqueCTE'

      # Estipulate a class name (which may contain namespace) that expose the
      # recursive auxiliary statement in order to perform detached CTEs
      cte.exposed_recursive_class = 'TorqueRecursiveCTE'

    end

    # Configure ENUM features
    config.nested(:enum) do |enum|

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
      enum.namespace = ::Object.const_set('Enum', Module.new)

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
  end
end
