module Torque
  module PostgreSQL
    module Base
      extend ActiveSupport::Concern

      module ClassMethods
        delegate :distinct_on, :with, :itself_only, :cast_records, to: :all

        # Wenever it's inherited, add a new list of auxiliary statements
        # It also adds an auxiliary statement to load inherited records' relname
        def inherited(subclass)
          super

          subclass.class_attribute(:auxiliary_statements_list)
          subclass.auxiliary_statements_list = {}

          record_class = ActiveRecord::Relation._record_class_attribute

          # Define helper methods to return the class of the given records
          subclass.auxiliary_statement record_class do |cte|
            pg_class = ::Arel::Table.new('pg_class')
            arel_query = ::Arel::SelectManager.new(pg_class)
            arel_query.project(pg_class['oid'], pg_class['relname'].as(record_class.to_s))

            cte.query 'pg_class', arel_query.to_sql
            cte.attributes col(record_class) => record_class
            cte.join tableoid: :oid
          end

          # Define the dynamic attribute that returns the same information as
          # the one provided by the auxiliary statement
          subclass.dynamic_attribute(record_class) do
            next self.class.table_name unless self.class.physically_inheritances?

            pg_class = ::Arel::Table.new('pg_class')
            source = ::Arel::Table.new(subclass.table_name, as: 'source')
            quoted_id = ::Arel::Nodes::Quoted.new(self.class.connection.quote(id))

            query = ::Arel::SelectManager.new(pg_class)
            query.join(source).on(pg_class['oid'].eq(source['tableoid']))
            query.where(source[subclass.primary_key].eq(quoted_id))
            query.project(pg_class['relname'])

            self.class.connection.select_value(query)
          end
        end

        protected

          # Allow optional select attributes to be loaded manually when they are
          # not present. This is associated with auxiliary statement, which
          # permits columns that can be loaded through CTEs, be loaded
          # individually for a single record
          #
          # For instance, if you have a statement that can load an user's last
          # comment content, by querying the comments using an auxiliary
          # statement.
          #   subclass.auxiliary_statement :last_comment do |cte|
          #     cte.query Comment.order(:user_id, id: :desc)
          #       .distinct_on(:user_id)
          #     cte.attributes col(:content) => :last_comment
          #     cte.join_type :left
          #   end
          #
          # In case you don't use 'with(:last_comment)', you can do the
          # following.
          #   dynamic_attribute(:last_comment) do
          #     comments.order(id: :desc).first.content
          #   end
          #
          # This means that any auxiliary statements can have their columns
          # granted even when they are not used
          def dynamic_attribute(name, &block)
            define_method(name) do
              return read_attribute(name) if has_attribute?(name)
              result = self.instance_exec(&block)

              type_klass = ActiveRecord::Type.respond_to?(:default_value) \
                ? ActiveRecord::Type.default_value \
                : self.class.connection.type_map.send(:default_value)

              @attributes[name.to_s] = ActiveRecord::Relation::QueryAttribute.new(
                name.to_s, result, type_klass,
              )

              read_attribute(name)
            end
          end

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
