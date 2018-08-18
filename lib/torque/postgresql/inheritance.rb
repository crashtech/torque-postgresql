module Torque
  module PostgreSQL
    InheritanceError = Class.new(ArgumentError)

    module Inheritance
      extend ActiveSupport::Concern

      # Cast the given object to its correct class
      def cast_inheritance
        record_class_value = send(self.class.record_class)

        return self unless self.class.table_name != record_class_value
        klass = self.class.casted_dependents[record_class_value]
        self.class.raise_unable_to_cast(record_class_value) if klass.nil?

        # The record need to be re-queried to have its attributes loaded
        # :TODO: Improve this by only loading the necessary extra columns
        klass.find(self.id)
      end

      private

        def using_single_table_inheritance?(record) # :nodoc:
          self.class.physically_inherited? || super
        end

      module ClassMethods

        # Easy and storable way to access the name used to get the record table
        # name when using inheritance tables
        def record_class
          @@record_class ||= Torque::PostgreSQL.config
            .inheritance.record_class_column_name.to_sym
        end

        # Easy and storable way to access the name used to get the indicater of
        # auto casting inherited records
        def auto_cast
          @@auto_cast ||= Torque::PostgreSQL.config
            .inheritance.auto_cast_column_name.to_sym
        end

        # Easy ans storable way have the arel column that identifies autp cast
        def auto_caster_marker
          @@auto_caster_marker ||= ::Arel::Nodes::SqlLiteral.new('TRUE')
            .as(auto_cast.to_s)
        end

        # Manually set the model name associated with tables name in order to
        # facilitates the identification of inherited records
        def inherited(subclass)
          super

          return unless Torque::PostgreSQL.config.eager_load &&
            !subclass.abstract_class?

          connection.schema_cache.add_model_name(table_name, subclass)
        end

        # Check if the model's table depends on any inheritance
        def physically_inherited?
          @physically_inherited ||= connection.schema_cache.dependencies(
            defined?(@table_name) ? @table_name : decorated_table_name,
          ).present?
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

        # Get the final decorated table, regardless of any special condition
        def decorated_table_name
          if parent < Base && !parent.abstract_class?
            contained = parent.table_name
            contained = contained.singularize if parent.pluralize_table_names
            contained += "_"
          end

          "#{full_table_name_prefix}#{contained}#{undecorated_table_name(name)}#{full_table_name_suffix}"
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
          raise InheritanceError.new(<<~MSG.squish) if klass.nil?
            An record was not able to be casted to type '#{record_class_value}'.
            If this table name doesn't represent a guessable model,
            please use 'Torque::PostgreSQL.conf.irregular_models =
            { '#{record_class_value}' => 'ModelName' }'.
          MSG
        end

        private

          def discriminate_class_for_record(record) # :nodoc:
            return super unless record.key?(record_class.to_s) &&
              record.key?(auto_cast.to_s) && record[record_class.to_s] != table_name

            klass = casted_dependents[record[record_class.to_s]]
            raise_unable_to_cast(record[record_class.to_s]) if klass.nil?
            klass
          end

      end
    end

    ActiveRecord::Base.include Inheritance
  end
end
