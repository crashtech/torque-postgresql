# frozen_string_literal: true

module Torque
  module PostgreSQL
    InheritanceError = Class.new(ArgumentError)

    module Inheritance
      extend ActiveSupport::Concern

      # Cast the given object to its correct class
      def cast_record
        record_class_value = send(self.class._record_class_attribute)

        return self unless self.class.table_name != record_class_value
        klass = self.class.casted_dependents[record_class_value]
        self.class.raise_unable_to_cast(record_class_value) if klass.nil?

        # The record need to be re-queried to have its attributes loaded
        # :TODO: Improve this by only loading the necessary extra columns
        klass.find(self.id)
      end

      module ClassMethods
        delegate :_auto_cast_attribute, :_record_class_attribute, to: ActiveRecord::Relation

        # Get a full list of all attributes from a model and all its dependents
        def inheritance_merged_attributes
          @inheritance_merged_attributes ||= begin
            list = attribute_names
            list += casted_dependents.values.map(&:attribute_names)
            list.flatten.uniq.freeze
          end
        end

        # Get the list of attributes that can be merged while querying because
        # they all have the same type
        def inheritance_mergeable_attributes
          @inheritance_mergeable_attributes ||= begin
            base = inheritance_merged_attributes - attribute_names
            types = base.zip(base.size.times.map { [] }).to_h

            casted_dependents.values.each do |klass|
              klass.attribute_types.each do |column, type|
                types[column]&.push(type)
              end
            end

            result = types.select do
              |_, types| types.each_with_object(types.shift).all?(&:==)
            end.keys + attribute_names

            result.freeze
          end
        end

        # Check if the model's table depends on any inheritance
        def physically_inherited?
          @physically_inherited ||= connection.schema_cache.dependencies(
            defined?(@table_name) ? @table_name : decorated_table_name,
          ).present?
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
          inheritance_dependents.present?
        end

        # Get the list of all ActiveRecord classes directly or indirectly
        # associated by inheritance
        def casted_dependents
          @casted_dependents ||= inheritance_dependents.map do |table_name|
            [table_name, connection.schema_cache.lookup_model(table_name)]
          end.to_h
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
          return super unless physically_inherited?
          self
        end

        # Primary key is one exception when getting information about the class,
        # it must returns the superclass PK
        def primary_key
          return super unless physically_inherited?
          superclass.primary_key
        end

        # Add an additional check to return the name of the table even when the
        # class is inherited, but only if it is a physical inheritance
        def compute_table_name
          return super unless physically_inherited?
          decorated_table_name
        end

        # Raises an error message saying that the giver record class was not
        # able to be casted since the model was not identified
        def raise_unable_to_cast(record_class_value)
          raise InheritanceError.new(<<~MSG.squish)
            An record was not able to be casted to type '#{record_class_value}'.
            If this table name doesn't represent a guessable model,
            please use 'Torque::PostgreSQL.conf.irregular_models =
            { '#{record_class_value}' => 'ModelName' }'.
          MSG
        end

        private

          def instantiate_instance_of(klass, attributes, column_types = {}, &block)
            return super unless klass.physically_inheritances?

            auto_cast = _auto_cast_attribute.to_s
            record_class = _record_class_attribute.to_s
            return super unless attributes.key?(record_class) &&
               attributes.delete(auto_cast) && attributes[record_class] != table_name

            klass = casted_dependents[attributes[record_class]]
            raise_unable_to_cast(attributes[record_class]) if klass.nil?
            filter_attributes_for_cast(attributes, klass)

            super(klass, attributes, column_types, &block)
          end

          # Filter the record attributes to be loaded to not included those from
          # another inherited dependent
          def filter_attributes_for_cast(record, klass)
            new_record = record.slice(*klass.attribute_names)
            table = new_record[_record_class_attribute.to_s] = klass.table_name

            # Recover aliased attributes
            (klass.attribute_names - inheritance_mergeable_attributes).each do |attribute|
              new_record[attribute] = record["#{table}__#{attribute}"]
            end

            # Add any additional columns and replace the record with the new record data
            new_record.merge!(record.slice(*(record.keys - inheritance_merged_attributes)))
            record.replace(new_record)
          end

      end
    end

    ActiveRecord::Base.include Inheritance
  end
end
