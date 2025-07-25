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

      class_methods do
        delegate :_auto_cast_attribute, :_record_class_attribute, to: ActiveRecord::Relation

        # Get a full list of all attributes from a model and all its dependents
        def inheritance_merged_attributes
          @inheritance_merged_attributes ||= begin
            children = casted_dependents.values.flat_map(&:attribute_names)
            attribute_names.to_set.merge(children).to_a.freeze
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

            result = types.filter_map do |attribute, types|
              attribute if types.each_with_object(types.shift).all?(&:==)
            end

            (attribute_names + result).freeze
          end
        end

        # Check if the model's table depends on any inheritance
        def physically_inherited?
          return @physically_inherited if defined?(@physically_inherited)

          @physically_inherited = connection.schema_cache.dependencies(
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

          # If the class is physically inherited, the klass needs to be properly
          # changed before moving forward
          def instantiate_instance_of(klass, attributes, types = {}, &block)
            return super unless klass.physically_inheritances?

            real_class = torque_discriminate_class_for_record(klass, attributes)
            return super if real_class.nil?

            attributes, types = sanitize_attributes(real_class, attributes, types)
            super(real_class, attributes, types, &block)
          end

          # Unwrap the attributes and column types from the given class when
          # there are unmergeable attributes
          def sanitize_attributes(real_class, attributes, types)
            skip = (inheritance_merged_attributes - real_class.attribute_names).to_set
            skip.merge(real_class.attribute_names - inheritance_mergeable_attributes)
            return [attributes, types] if skip.empty?

            dropped = 0
            new_types = {}

            row = attributes.instance_variable_get(:@row).dup
            indexes = attributes.instance_variable_get(:@column_indexes).dup
            indexes = indexes.each_with_object({}) do |(column, index), new_indexes|
              attribute, prefix = column.split('__', 2).reverse
              current_index = index - dropped

              if prefix != table_name && skip.include?(attribute)
                row.delete_at(current_index)
                dropped += 1
              else
                new_types.merge!(types.slice(attribute))
                new_types[current_index] = types[index]
                new_indexes[attribute] = current_index
              end
            end

            [ActiveRecord::Result::IndexedRow.new(indexes, row), new_types]
          end

          # Get the real class when handling physical inheritances and casting
          # the record when existing properly is present
          def torque_discriminate_class_for_record(klass, record)
            return if record[_auto_cast_attribute.to_s] == false

            embedded_type = record[_record_class_attribute.to_s]
            return if embedded_type.blank? || embedded_type == table_name

            casted_dependents[embedded_type] || raise_unable_to_cast(embedded_type)
          end
      end
    end

    ActiveRecord::Base.include Inheritance
  end
end
