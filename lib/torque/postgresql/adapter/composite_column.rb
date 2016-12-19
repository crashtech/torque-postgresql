module Torque
  module PostgreSQL
    module Adapter

      class CompositeColumn < ActiveRecord::ConnectionAdapters::PostgreSQLColumn
        attr_reader :type_name

        undef :table_name

        def initialize(name, default, sql_type_metadata = nil, null = true,
                       type_name = nil, default_function = nil, collation = nil,
                       comment: nil)
          @name = name.freeze
          @type_name = type_name
          @sql_type_metadata = sql_type_metadata
          @null = null
          @default = default
          @default_function = default_function
          @collation = collation
          @comment = comment
        end

        protected

          def attributes_for_hash
            [
              self.class,
              name,
              default,
              sql_type_metadata,
              null,
              type_name,default_function,
              collation
            ]
          end

      end

    end
  end
end
