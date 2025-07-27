module Mocks
  module CreateTable
    def mock_create_table
      around do |example|
        original_method = ActiveRecord::Base.connection.method(:log)
        original_method.receiver.define_singleton_method(:log) do |sql, *, **, &block|
          sql
        end

        example.run
        original_method.receiver.define_singleton_method(:log, &original_method.to_proc)
      end
    end
  end
end
