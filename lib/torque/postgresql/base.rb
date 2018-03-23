module Torque
  module PostgreSQL
    module Base
      extend ActiveSupport::Concern

      module ClassMethods
        delegate :distinct_on, :with, to: :all

        private

          # Wenever it's inherited, add a new list of auxiliary statements
          def inherited(subclass)
            subclass.class_attribute(:auxiliary_statements_list)
            subclass.auxiliary_statements_list = Hash.new
            super
          end

        protected

          # Creates a new auxiliary statement (CTE) under the base class
          # attributes key:
          # Provides a map of attributes to be exposed to the main query.
          #
          # For instace, if the statement query has an 'id' column that you
          # want it to be accessed on the main query as 'item_id',
          # you can use:
          #   attributes id: :item_id, 'MAX(id)' => :max_id,
          #     col(:id).minimum => :min_id
          #
          # If its statement has more tables, and you want to expose those
          # fields, then:
          #   attributes 'table.name': :item_name
          #
          # join_type key:
          # Changes the type of the join and set the constraints
          #
          # The left side of the hash is the source table column, the right
          # side is the statement table column, now it's only accepting '='
          # constraints
          #   join id: :user_id
          #   join id: :'user.id'
          #   join 'post.id': :'user.last_post_id'
          #
          # It's possible to change the default type of join
          #   join :left, id: :user_id
          #
          # join key:
          # Changes the type of the join
          #
          # query key:
          # Save the query command to be performand
          #
          # requires key:
          # Indicates dependencies with another statements
          #
          # polymorphic key:
          # Indicates a polymorphic relationship, with will affect the way the
          # auto join works, by giving a polymorphic connection
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
