module Torque
  module PostgreSQL
    InheritanceError = Class.new(ArgumentError)

    module Inheritance
      extend ActiveSupport::Concern

      # Cast the given object to its correct class
      # :TODO: gems/activerecord-5.1.6/lib/active_record/persistence.rb:66
      def cast_inheritance
        return self unless self.class.table_name != _record_class
        klass = self.class.casted_dependents[_record_class]

        # Raises an error when the record class is not an inheritance of the
        # current class
        raise InheritanceError.new(<<~MSG.squish) if klass.nil?
          The instance '#{self.inspect}' was not able to be casted to type '#{_record_class}'.
          If this table name doesn't represent a guessable model, please use
          'Torque::PostgreSQL.conf.irregular_models = { '#{_record_class}' => 'ModelName' }'.
        MSG

        # The record need to be re-queried to have its attributes loaded
        # :TODO: Improve this by only loading the necessary extra columns
        klass.find(self.id)
      end

      private

        def using_single_table_inheritance?(record) # :nodoc:
          self.class.physically_inherited? || super
        end

      module ClassMethods

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
          connection.schema_cache.associations(table_name)
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

          # Add an additional check to return the name of the table even when
          # the class is inherited, but only if it is a physical inheritance
          def compute_table_name
            return super unless physically_inherited?
            decorated_table_name
          end

      end
    end

    ActiveRecord::Base.include Inheritance
  end
end
