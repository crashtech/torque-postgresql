module Torque
  module PostgreSQL
    include ActiveSupport::Configurable

    # Stores a version check for compatibility purposes
    AR521 = (ActiveRecord.gem_version >= Gem::Version.new('5.2.1'))

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

    # Configure ENUM features
    config.nested(:enum) do |enum|

      # Indicates if the enum features on ActiveRecord::Base should be initiated
      # automatically or not
      enum.initializer = false

      # The name of the method to be used on any ActiveRecord::Base to
      # initialize model-based enum features
      enum.base_method = :enum

      # Indicates if bang methods like 'disabled!' should update the record on
      # database or not
      enum.save_on_bang = true

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

    # Configure auxiliary statement features
    config.nested(:auxiliary_statement) do |cte|

      # Define the key that is used on auxiliary statements to send extra
      # arguments to format string or send on a proc
      cte.send_arguments_key = :args

      # Specify the namespace of each enum type of value
      cte.exposed_class = 'TorqueCTE'

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

    # Configure geometry data types
    config.nested(:geometry) do |geometry|

      # Define the class that will be handling Point data types after decoding
      # it. Any class provided here must respond to 'x', and 'y'
      geometry.point_class = ActiveRecord::Point

      # Define the class that will be handling Circle data types after decoding
      # it. Any class provided here must respond to 'x', 'y', and 'r'
      geometry.circle_class = nil

      # Define the class that will be handling Box data types after decoding it.
      # Any class provided here must respond to 'x1', 'y1', 'x2', and 'y2'
      geometry.box_class = nil

      # Define the class that will be handling Line data types after decoding
      # it. Any class provided here must respond to 'a', 'b', and 'c'
      geometry.line_class = nil

      # Define the class that will be handling Segment data types after decoding
      # it. Any class provided here must respond to 'x1', 'y1', 'x2', and 'y2'
      geometry.segment_class = nil

    end

  end
end
