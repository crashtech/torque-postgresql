# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module ColumnMethods

        # Adds a search language column to the table. See +add_search_language+
        def search_language(*names, **options)
          raise ArgumentError, "Missing column name(s) for search_language" if names.empty?
          names.each { |name| column(name, :regconfig, **options) }
        end

        # Add a search vector column to the table. See +add_search_vector+
        def search_vector(*names, columns:, **options)
          raise ArgumentError, "Missing column name(s) for search_vector" if names.empty?
          options = Attributes::Builder.search_vector_options(columns: columns, **options)
          names.each { |name| column(name, :virtual, **options) }
        end

      end

      module TableDefinition
        include ColumnMethods

        attr_reader :inherits

        def initialize(*args, **options)
          super

          @inherits = Array.wrap(options.delete(:inherits)).flatten.compact \
            if options.key?(:inherits)
        end

        def set_primary_key(tn, id, primary_key, *, **)
          super unless @inherits.present? && primary_key.blank? && id == :primary_key
        end

        private

          def create_column_definition(name, type, options)
            if type == :enum_set
              type = :enum
              options ||= {}
              options[:array] = true
            end

            super(name, type, options)
          end
      end

      ActiveRecord::ConnectionAdapters::PostgreSQL::Table.include ColumnMethods
      ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.include TableDefinition
    end
  end
end
