# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module SchemaOverrides
        # This adds better support for handling the quotation of table names
        def quote_table_name(name)
          ActiveRecord::ConnectionAdapters::PostgreSQL::Quoting::QUOTED_TABLE_NAMES.then do |m|
            m[name] ||= quote_identifier_name(name)
          end
        end

        %i[
          table_exists? indexes index_exists? columns column_exists? primary_key
          create_table change_table add_column add_columns remove_columns remove_column
          change_column change_column_default change_column_null rename_column
          add_index remove_index rename_index index_name_exists? foreign_keys
          add_timestamps remove_timestamps change_table_comment change_column_comment
          bulk_change_table

          rename_table add_foreign_key remove_foreign_key foreign_key_exists?
        ].each do |method_name|
          define_method(method_name) do |table_name, *args, **options, &block|
            table_name = sanitize_name_with_schema(table_name, options)
            super(table_name, *args, **options, &block)
          end
        end

        def drop_table(*table_names, **options)
          table_names = table_names.map { |name| sanitize_name_with_schema(name, options.dup) }
          super(*table_names, **options)
        end

        private

          def validate_table_length!(table_name)
            super(table_name.to_s)
          end
      end

      include SchemaOverrides
    end
  end
end
