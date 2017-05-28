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

      module TableDefinition
        include ColumnMethods

        attr_reader :inherits

        def initialize(name, *args, **options)
          old_args = []
          old_args << options.delete(:temporary) || false
          old_args << options.delete(:options)
          old_args << options.delete(:as)
          comment = options.delete(:comment)

          super(name, *old_args, comment: comment)

          if options.key?(:inherits)
            @inherits = Array[options.delete(:inherits)].flatten.compact
            @inherited_id = !(options.key?(:primary_key) || options.key?(:id))
          end
        end

        def inherited_id?
          @inherited_id
        end
      end

      ActiveRecord::ConnectionAdapters::PostgreSQL::Table.include ColumnMethods
      ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.include TableDefinition

      if ActiveRecord::ConnectionAdapters::PostgreSQL.const_defined?('ColumnDefinition')
        module ColumnDefinition
          attr_accessor :subtype
        end

        ActiveRecord::ConnectionAdapters::PostgreSQL::ColumnDefinition.include ColumnDefinition
      end
    end
  end
end
