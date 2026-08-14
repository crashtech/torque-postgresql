# frozen_string_literal: true

require_relative 'inheritance/record'
require_relative 'inheritance/expander'

module Torque
  module PostgreSQL
    InheritanceError = Class.new(ArgumentError)

    module Inheritance
      extend ActiveSupport::Concern

      class_methods do
        delegate :_record_class_attribute, :_record_class_column_name, to: ActiveRecord::Relation

        # Get a full list of all attributes from a model and all its dependents
        def inheritance_merged_attributes
          inheritance_cache(:@inheritance_merged_attributes) do
            children = casted_dependents.values.flat_map(&:attribute_names)
            attribute_names.to_set.merge(children).to_a.freeze
          end
        end

        # Get the list of attributes that can be merged while querying because
        # they all have the same type
        def inheritance_mergeable_attributes
          inheritance_cache(:@inheritance_mergeable_attributes) do
            base = inheritance_merged_attributes - attribute_names
            types = base.zip(base.size.times.map { [] }).to_h

            casted_dependents.values.each do |klass|
              klass.attribute_types.each do |column, type|
                types[column]&.push(type)
              end
            end

            result = types.filter_map do |attribute, types|
              attribute if types.each_with_object(types.shift).all?(&:==)
            end

            (attribute_names + result).freeze
          end
        end

        # Check if the model's table depends on any inheritance
        def physically_inherited?
          inheritance_cache(:@physically_inherited) do
            connection.schema_cache.dependencies(
              defined?(@table_name) ? @table_name : decorated_table_name,
            ).present?
          end
        rescue ActiveRecord::ConnectionNotEstablished
          false
        end

        # Get the list of all tables directly or indirectly dependent of the
        # current one
        def inheritance_dependents
          connection.schema_cache.associations(table_name) || []
        end

        # Check whether the model's table has directly or indirectly dependents
        def physically_inheritances?
          inheritance_cache(:@physically_inheritances) { inheritance_dependents.present? }
        end

        # The prefix that identifies the columns of this table when they are
        # loaded next to the columns of a sibling table
        def inheritance_column_prefix
          inheritance_cache(:@inheritance_column_prefix) { "#{table_name}__".freeze }
        end

        # The topmost class of this class' physical inheritance family, which
        # is what casted_dependents needs to be called on to see every
        # dependent in the family rather than just this class' own descendants
        def physically_inheritance_root
          physically_inherited? ? superclass.physically_inheritance_root : self
        end

        # The columns that belong to other dependents of this class' physical
        # inheritance family, which must never land on one of its casted
        # records because they belong to a sibling, not to this class
        def inheritance_foreign_attribute_names
          inheritance_cache(:@inheritance_foreign_attribute_names) do
            (physically_inheritance_root.inheritance_merged_attributes - attribute_names).to_set.freeze
          end
        end

        # The exact "table_name__" prefixes build_inheritances emits for a
        # non-mergeable column of any dependent in this class' physical
        # inheritance family, which is what a joined sibling column looks like
        def inheritance_dependent_prefixes
          inheritance_cache(:@inheritance_dependent_prefixes) do
            physically_inheritance_root.casted_dependents.keys.map { |name| "#{name}__" }.to_set.freeze
          end
        end

        # Get the list of all ActiveRecord classes directly or indirectly
        # associated by inheritance
        def casted_dependents
          inheritance_cache(:@casted_dependents) do
            inheritance_dependents.map do |table_name|
              [table_name, connection.schema_cache.lookup_model(table_name)]
            end.to_h.freeze
          end
        end

        # Get the dependents that actually add columns, which are the only ones
        # that produce incomplete records when loaded from this table
        def inheritance_expandable_dependents
          inheritance_cache(:@inheritance_expandable_dependents) do
            casted_dependents.select do |_table_name, klass|
              (klass.attribute_names - attribute_names).any?
            end.freeze
          end
        end

        # Manually set the model name associated with tables name in order to
        # facilitates the identification of inherited records
        def reset_table_name
          table = super

          adapter = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
          if Torque::PostgreSQL.config.eager_load && connection.is_a?(adapter)
            connection.schema_cache.add_model_name(table, self)
          end

          table
        end

        # Get the final decorated table, regardless of any special condition
        def decorated_table_name
          parent_class = try(:module_parent) || try(:parent)
          if parent_class < Base && !parent_class.abstract_class?
            contained = parent_class.table_name
            contained = contained.singularize if parent_class.pluralize_table_names
            contained += "_"
          end

          "#{full_table_name_prefix}#{contained}#{undecorated_table_name(name)}#{full_table_name_suffix}"
        end

        # For all main purposes, physical inherited classes should have
        # base_class as their own
        def base_class
          physically_inherited? ? self : super
        end

        # Primary key is one exception when getting information about the class,
        # it must returns the superclass PK
        def primary_key
          physically_inherited? ? superclass.primary_key : super
        end

        # Add an additional check to return the name of the table even when the
        # class is inherited, but only if it is a physical inheritance
        def compute_table_name
          physically_inherited? ? decorated_table_name : super
        end

        # Raises an error message saying that the given record class could not
        # be instantiated since the model was not identified
        def raise_unable_to_cast(record_class_value)
          raise InheritanceError.new(<<~MSG.squish)
            A record could not be instantiated as '#{record_class_value}'.
            If this table name doesn't represent a guessable model,
            please use 'Torque::PostgreSQL.conf.irregular_models =
            { '#{record_class_value}' => 'ModelName' }'.
          MSG
        end

        protected

          # Inheritance metadata is derived from the schema, so it must be
          # dropped whenever ActiveRecord drops its own schema-derived caches
          def reload_schema_from_cache(recursive = true)
            @physically_inherited = nil
            @physically_inheritances = nil
            @casted_dependents = nil
            @inheritance_merged_attributes = nil
            @inheritance_mergeable_attributes = nil
            @inheritance_expandable_dependents = nil
            @inheritance_column_prefix = nil
            @inheritance_foreign_attribute_names = nil
            @inheritance_dependent_prefixes = nil
            super
          end

        private

          # Memoize using double-checked locking against ActiveRecord's own
          # monitor for loading the schema
          def inheritance_cache(name)
            current = instance_variable_get(name)
            return current unless current.nil?

            # why: @load_schema_monitor is still nil while AR's inherited reaches base_class
            (@load_schema_monitor ||= Monitor.new).synchronize do
              current = instance_variable_get(name)
              return current unless current.nil?

              instance_variable_set(name, yield)
            end
          end

          # Rows coming from a table with dependents carry the table they were
          # stored in, which is what decides the class to instantiate
          def instantiate_instance_of(klass, attributes, types = {}, &block)
            return super unless klass.physically_inheritances?

            marker = _record_class_column_name
            record_class = attributes[marker]
            if record_class.blank? || record_class == klass.table_name
              values, types = sanitize_attributes(klass, attributes, types)
              return super(klass, values, types, &block)
            end

            real_class = klass.casted_dependents[record_class]
            klass.raise_unable_to_cast(record_class) if real_class.nil?

            values, types = sanitize_attributes(real_class, attributes, types)
            record = super(real_class, values, types, &block)

            # why: expand_records may already join in real_class's own columns
            if klass.inheritance_expandable_dependents.key?(record_class)
              incomplete = real_class.attribute_names.any? { |name| !values.key?(name) }
              record.send(:mark_as_partial_record!) if incomplete
            end

            record
          end

          # Drop what is known to be foreign: the internal record class column
          # and the columns prefixed with another dependent table of the same
          # family, unwrapping our own prefix and letting everything else
          # through, including a user alias that happens to contain '__'
          def sanitize_attributes(real_class, attributes, types)
            prefix = real_class.inheritance_column_prefix
            sibling_prefixes = real_class.inheritance_dependent_prefixes
            foreign = real_class.inheritance_foreign_attribute_names
            skip = _record_class_column_name

            new_values = {}
            new_types = {}

            attributes.to_hash.each do |column, value|
              next if column == skip || foreign.include?(column)

              name =
                if column.start_with?(prefix)
                  column.delete_prefix(prefix)
                elsif sibling_prefixes.any? { |sibling_prefix| column.start_with?(sibling_prefix) }
                  next
                else
                  column
                end

              new_values[name] = value
              new_types[name] = types[column] if types.key?(column)
            end

            [new_values, new_types]
          end
      end
    end

    ActiveRecord::Base.include Inheritance
    ActiveRecord::Base.include Inheritance::Record
  end
end
