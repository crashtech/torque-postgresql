module Torque
  module PostgreSQL
    module Adapter
      module ColumnMethods

        def interval(*args, **options)
          args.each { |name| column(name, :interval, options) }
        end

        def enum(*args, **options)
          args.each do |name|
            type = options.fetch(:subtype, name)
            column(name, type, options)
          end
        end

        def composite(*args, **options)
          args.each do |name|
            type = options.fetch(:subtype, name)
            column(name, type, options)
          end
        end

      end

      module ColumnDefinition
        attr_accessor :subtype
      end

      class CompositeTypeDefinition < ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition

        undef :indexes, :indexes=, :temporary, :foreign_keys, :comment
        undef :primary_keys, :index, :foreign_key, :timestamps

        def initialize(name, options = nil, as = nil)
          @columns_hash = {}
          @options = options
          @as = as
          @name = name
        end

      end

      ActiveRecord::ConnectionAdapters::PostgreSQL::Table.include ColumnMethods
      ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.include ColumnMethods
      ActiveRecord::ConnectionAdapters::PostgreSQL::ColumnDefinition.include ColumnDefinition
    end
  end
end
