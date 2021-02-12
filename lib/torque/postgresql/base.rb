# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Base
      extend ActiveSupport::Concern

      included do
        mattr_accessor :belongs_to_many_required_by_default, instance_accessor: false
      end

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

        # Specifies a one-to-many association. The following methods for
        # retrieval and query of collections of associated objects will be
        # added:
        #
        # +collection+ is a placeholder for the symbol passed as the +name+
        # argument, so <tt>belongs_to_many :tags</tt> would add among others
        # <tt>tags.empty?</tt>.
        #
        # [collection]
        #   Returns a Relation of all the associated objects.
        #   An empty Relation is returned if none are found.
        # [collection<<(object, ...)]
        #   Adds one or more objects to the collection by adding their ids to
        #   the array of ids on the parent object.
        #   Note that this operation instantly fires update SQL without waiting
        #   for the save or update call on the parent object, unless the parent
        #   object is a new record.
        #   This will also run validations and callbacks of associated
        #   object(s).
        # [collection.delete(object, ...)]
        #   Removes one or more objects from the collection by removing their
        #   ids from the list on the parent object.
        #   Objects will be in addition destroyed if they're associated with
        #   <tt>dependent: :destroy</tt>, and deleted if they're associated
        #   with <tt>dependent: :delete_all</tt>.
        # [collection.destroy(object, ...)]
        #   Removes one or more objects from the collection by running
        #   <tt>destroy</tt> on each record, regardless of any dependent option,
        #   ensuring callbacks are run. They will also be removed from the list
        #   on the parent object.
        # [collection=objects]
        #   Replaces the collections content by deleting and adding objects as
        #   appropriate.
        # [collection_singular_ids]
        #   Returns an array of the associated objects' ids
        # [collection_singular_ids=ids]
        #   Replace the collection with the objects identified by the primary
        #   keys in +ids+. This method loads the models and calls
        #   <tt>collection=</tt>. See above.
        # [collection.clear]
        #   Removes every object from the collection. This destroys the
        #   associated objects if they are associated with
        #   <tt>dependent: :destroy</tt>, deletes them directly from the
        #   database if <tt>dependent: :delete_all</tt>, otherwise just remove
        #   them from the list on the parent object.
        # [collection.empty?]
        #   Returns +true+ if there are no associated objects.
        # [collection.size]
        #   Returns the number of associated objects.
        # [collection.find(...)]
        #   Finds an associated object according to the same rules as
        #   ActiveRecord::FinderMethods#find.
        # [collection.exists?(...)]
        #   Checks whether an associated object with the given conditions exists.
        #   Uses the same rules as ActiveRecord::FinderMethods#exists?.
        # [collection.build(attributes = {}, ...)]
        #   Returns one or more new objects of the collection type that have
        #   been instantiated with +attributes+ and linked to this object by
        #   adding its +id+ to the list after saving.
        # [collection.create(attributes = {})]
        #   Returns a new object of the collection type that has been
        #   instantiated with +attributes+, linked to this object by adding its
        #   +id+ to the list after performing the save (if it passed the
        #   validation).
        # [collection.create!(attributes = {})]
        #   Does the same as <tt>collection.create</tt>, but raises
        #   ActiveRecord::RecordInvalid if the record is invalid.
        # [collection.reload]
        #   Returns a Relation of all of the associated objects, forcing a
        #   database read. An empty Relation is returned if none are found.
        #
        # === Example
        #
        # A <tt>Video</tt> class declares <tt>belongs_to_many :tags</tt>,
        # which will add:
        # * <tt>Video#tags</tt> (similar to <tt>Tag.where([id] && tag_ids)</tt>)
        # * <tt>Video#tags<<</tt>
        # * <tt>Video#tags.delete</tt>
        # * <tt>Video#tags.destroy</tt>
        # * <tt>Video#tags=</tt>
        # * <tt>Video#tag_ids</tt>
        # * <tt>Video#tag_ids=</tt>
        # * <tt>Video#tags.clear</tt>
        # * <tt>Video#tags.empty?</tt>
        # * <tt>Video#tags.size</tt>
        # * <tt>Video#tags.find</tt>
        # * <tt>Video#tags.exists?(name: 'ACME')</tt>
        # * <tt>Video#tags.build</tt>
        # * <tt>Video#tags.create</tt>
        # * <tt>Video#tags.create!</tt>
        # * <tt>Video#tags.reload</tt>
        # The declaration can also include an +options+ hash to specialize the
        # behavior of the association.
        #
        # === Options
        # [:class_name]
        #   Specify the class name of the association. Use it only if that name
        #   can't be inferred from the association name. So <tt>belongs_to_many
        #   :tags</tt> will by default be linked to the +Tag+ class, but if the
        #   real class name is +SpecialTag+, you'll have to specify it with this
        #   option.
        # [:foreign_key]
        #   Specify the foreign key used for the association. By default this is
        #   guessed to be the name of this class in lower-case and "_ids"
        #   suffixed. So a Video class that makes a #belongs_to_many association
        #   with Tag will use "tag_ids" as the default <tt>:foreign_key</tt>.
        #
        #   It is a good idea to set the <tt>:inverse_of</tt> option as well.
        # [:primary_key]
        #   Specify the name of the column to use as the primary key for the
        #   association. By default this is +id+.
        # [:dependent]
        #   Controls what happens to the associated objects when their owner is
        #   destroyed. Note that these are implemented as callbacks, and Rails
        #   executes callbacks in order. Therefore, other similar callbacks may
        #   affect the <tt>:dependent</tt> behavior, and the <tt>:dependent</tt>
        #   behavior may affect other callbacks.
        # [:touch]
        #   If true, the associated objects will be touched (the updated_at/on
        #   attributes set to current time) when this record is either saved or
        #   destroyed. If you specify a symbol, that attribute will be updated
        #   with the current time in addition to the updated_at/on attribute.
        #   Please note that with touching no validation is performed and only
        #   the +after_touch+, +after_commit+ and +after_rollback+ callbacks are
        #   executed.
        # [:optional]
        #   When set to +true+, the association will not have its presence
        #   validated.
        # [:required]
        #   When set to +true+, the association will also have its presence
        #   validated. This will validate the association itself, not the id.
        #   You can use +:inverse_of+ to avoid an extra query during validation.
        #   NOTE: <tt>required</tt> is set to <tt>false</tt> by default and is
        #   deprecated. If you want to have association presence validated,
        #   use <tt>required: true</tt>.
        # [:default]
        #   Provide a callable (i.e. proc or lambda) to specify that the
        #   association should be initialized with a particular record before
        #   validation.
        # [:inverse_of]
        #   Specifies the name of the #has_many association on the associated
        #   object that is the inverse of this #belongs_to_many association.
        #   See ActiveRecord::Associations::ClassMethods's overview on
        #   Bi-directional associations for more detail.
        #
        # Option examples:
        #   belongs_to_many :tags, dependent: :nullify
        #   belongs_to_many :tags, required: true, touch: true
        #   belongs_to_many :tags, default: -> { Tag.default }
        def belongs_to_many(name, scope = nil, **options, &extension)
          klass = Associations::Builder::BelongsToMany
          reflection = klass.build(self, name, scope, options, &extension)
          ::ActiveRecord::Reflection.add_reflection(self, name, reflection)
        end

        # Allow extra keyword arguments to be sent to +InsertAll+
        def upsert_all(attributes, **xargs)
          xargs = xargs.merge(on_duplicate: :update)
          ::ActiveRecord::InsertAll.new(self, attributes, **xargs).execute
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

    ::ActiveRecord::Base.include(Base)
  end
end
