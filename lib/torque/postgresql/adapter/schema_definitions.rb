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

      end

      ActiveRecord::ConnectionAdapters::PostgreSQL::Table.include ColumnMethods
      ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.include ColumnMethods

      if ActiveRecord::ConnectionAdapters::PostgreSQL.const_defined?('ColumnDefinition')
        module ColumnDefinition
          attr_accessor :subtype
        end

        ActiveRecord::ConnectionAdapters::PostgreSQL::ColumnDefinition.include ColumnDefinition
      end
    end
  end
end
