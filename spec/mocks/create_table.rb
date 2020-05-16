module Mocks
  module CreateTable
    def mock_create_table
      path = ActiveRecord::Base.connection.method(:create_table).super_method.source_location[0]

      before :all do
        ActiveRecord::ConnectionAdapters::SchemaStatements.send(:define_method, :create_table) do |table_name, **options, &block|
          td = create_table_definition(table_name, **options)

          # Does things as the same as schema statements
          if options[:id] != false && !options[:as]
            pk = options.fetch(:primary_key) do
              ActiveRecord::Base.get_primary_key table_name.to_s.singularize
            end

            if pk.is_a?(Array)
              td.primary_keys pk
            else
              td.primary_key pk, options.fetch(:id, :primary_key), **options
            end
          end

          block.call(td) if block.present?

          # Now generate the SQL and return it
          schema_creation.accept td
        end
      end

      after :all do
        load path
      end
    end
  end
end
