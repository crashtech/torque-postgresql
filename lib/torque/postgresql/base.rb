module Torque
  module PostgreSQL
    module Base
      extend ActiveSupport::Concern

      included do
        class_attribute :auxiliary_statements_list, instance_accessor: true
        self.auxiliary_statements_list = {}
      end

      module ClassMethods
        delegate :distinct_on, :with, to: :all

        protected

          # Creates a new auxiliary statement (CTE) under the base class
          def auxiliary_statement(table, &block)
            klass = AuxiliaryStatement.lookup(table, self)
            auxiliary_statements_list[table.to_sym] = klass
            klass.configurator(block)
          end
          alias cte auxiliary_statement
      end
    end

    ActiveRecord::Base.include Base
  end
end
