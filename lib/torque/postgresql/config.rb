module Torque
  module PostgreSQL
    include ActiveSupport::Configurable

    # Allow nested configurations
    config.define_singleton_method(:nested) do |name, &block|
      klass = Class.new(ActiveSupport::Configurable::Configuration).new
      block.call(klass) if block
      send("#{name}=", klass)
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

  end
end
