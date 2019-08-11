require_relative 'auxiliary_statement/settings'

module Torque
  module PostgreSQL
    class AuxiliaryStatement
      TABLE_COLUMN_AS_STRING = /\A(?:"?(\w+)"?\.)?"?(\w+)"?\z/.freeze

      class << self
        # These attributes require that the class is setup
        #
        # The attributes separation means
        # exposed_attributes -> Will be projected to the main query
        # selected_attributes -> Will be selected on the configurated query
        # join_attributes -> Will be used to join the the queries
        [:exposed_attributes, :selected_attributes, :query, :join_attributes,
          :join_type, :requires].each do |attribute|
          define_method(attribute) do
            setup
            instance_variable_get("@#{attribute}")
          end
        end

        # Find or create the class that will handle statement
        def lookup(name, base)
          const = name.to_s.camelize << '_' << self.name.demodulize
          return base.const_get(const, false) if base.const_defined?(const, false)
          base.const_set(const, Class.new(AuxiliaryStatement))
        end

        # Create a new instance of an auxiliary statement
        def instantiate(statement, base, options = nil)
          klass = base.auxiliary_statements_list[statement]
          return klass.new(options) unless klass.nil?
          raise ArgumentError, <<-MSG.strip
            There's no '#{statement}' auxiliary statement defined for #{base.class.name}.
          MSG
        end

        # Identify if the query set may be used as a relation
        def relation_query?(obj)
          !obj.nil? && obj.respond_to?(:ancestors) && \
            obj.ancestors.include?(ActiveRecord::Base)
        end

        # Identify if the query set may be used as arel
        def arel_query?(obj)
          !obj.nil? && obj.is_a?(::Arel::SelectManager)
        end

        # A way to create auxiliary statements outside of models configurations,
        # being able to use on extensions
        def create(base, table_name = nil, &block)
          klass = Class.new(AuxiliaryStatement)
          klass.instance_variable_set(:@table_name, table_name)
          klass.instance_variable_set(:@base, base)
          klass.configurator(block)
          klass
        end

        # Set a configuration block, if the class is already set up, just clean
        # the query and wait it to be setup again
        def configurator(block)
          @config = block
          @query = nil
        end

        # Get the base class associated to this statement
        def base
          @base || self.parent
        end

        # Get the name of the base class
        def base_name
          base.name
        end

        # Get the arel version of the statement table
        def table
          @table ||= ::Arel::Table.new(table_name)
        end

        # Get the name of the table of the configurated statement
        def table_name
          @table_name ||= self.name.demodulize.split('_').first.underscore
        end

        # Get the arel table of the base class
        def base_table
          @base_table ||= base.arel_table
        end

        # Get the arel table of the query
        def query_table
          @query_table ||= query.arel_table
        end

        # Project a column on a given table, or use the column table
        def project(column, arel_table = nil)
          if column.respond_to?(:as)
            return column
          elsif (as_string = TABLE_COLUMN_AS_STRING.match(column.to_s))
            column = as_string[2]
            arel_table = ::Arel::Table.new(as_string[1]) unless as_string[1].nil?
          end

          arel_table ||= table
          arel_table[column.to_s]
        end

        private
          # Just setup the class if it's not setup
          def setup
            setup! unless setup?
          end

          # Check if the class is setup
          def setup?
            defined?(@query) && @query
          end

          # Setup the class
          def setup!
            settings = Settings.new(self)
            settings.instance_exec(settings, &@config)

            @join_type = settings.join_type || :inner
            @requires = Array[settings.requires].flatten.compact
            @query = settings.query

            # Manually set the query table when it's not an relation query
            @query_table = settings.query_table unless relation_query?(@query)

            # Reset all the used attributes
            @selected_attributes = []
            @exposed_attributes = []
            @join_attributes = []

            # Generate attributes projections
            attributes_projections(settings.attributes) if settings.attributes.present?

            # Generate join projections
            if settings.join.present?
              joins_projections(settings.join)
            elsif relation_query?(@query)
              check_auto_join(settings.polymorphic)
            else
              raise ArgumentError, <<-MSG.strip.gsub(/\n +/, ' ')
                You must provide the join columns when using '#{query.class.name}'
                as a query object on #{self.class.name}.
              MSG
            end
          end

          # Iterate the attributes settings
          # Attributes (left => right)
          #   left -> query.selected_attributes AS right
          #   right -> table.exposed_attributes
          def attributes_projections(list)
            list.each do |left, right|
              @exposed_attributes << project(right)
              @selected_attributes << project(left, query_table).as(right.to_s)
            end
          end

          # Iterate the join settings
          # Join (left => right)
          #   left -> base.join_attributes.eq(right)
          #   right -> table.selected_attributes
          def joins_projections(list)
            list.each do |left, right|
              @selected_attributes << project(right, query_table)
              @join_attributes << project(left, base_table).eq(project(right))
            end
          end

          # Check if it's possible to identify the connection between the main
          # query and the statement query
          #
          # First, identify the foreign key column name, then check if it exists
          # on the query and then create the projections
          def check_auto_join(polymorphic)
            foreign_key = (polymorphic.present? ? polymorphic : base_name)
            foreign_key = foreign_key.to_s.foreign_key
            if query.columns_hash.key?(foreign_key)
              joins_projections(base.primary_key => foreign_key)
              if polymorphic.present?
                foreign_type = foreign_key.gsub(/_id$/, '_type')
                @selected_attributes << project(foreign_type, query_table)
                @join_attributes << project(foreign_type).eq(base_name)
              end
            end
          end
      end

      delegate :exposed_attributes, :join_attributes, :selected_attributes, :join_type, :table,
               :query_table, :base_table, :requires, :project, :relation_query?, to: :class

      # Start a new auxiliary statement giving extra options
      def initialize(*args)
        options = args.extract_options!
        args_key = Torque::PostgreSQL.config.auxiliary_statement.send_arguments_key

        @join = options.fetch(:join, {})
        @args = options.fetch(args_key, {})
        @select = options.fetch(:select, {})
        @join_type = options.fetch(:join_type, join_type)
      end

      # Get the columns that will be selected for this statement
      def columns
        exposed_attributes + @select.values.map(&method(:project))
      end

      # Build the statement on the given arel and return the WITH statement
      def build_arel(arel, base)
        # Build the join for this statement
        arel.join(table, arel_join).on(*join_columns)

        # Return the subquery for this statement
        ::Arel::Nodes::As.new(table, mount_query)
      end

      # Get the bound attributes from statement qeury
      def bound_attributes
        return [] unless relation_query?(self.class.query)
        self.class.query.send(:bound_attributes)
      end

      # Ensure that all the dependencies are loaded in the base relation
      def ensure_dependencies!(base)
        requires.each do |dependent|
          dependent_klass = base.model.auxiliary_statements_list[dependent]
          next if base.auxiliary_statements_values.any? do |cte|
            cte.is_a?(dependent_klass)
          end

          instance = AuxiliaryStatement.instantiate(dependent, base)
          instance.ensure_dependencies!(base)
          base.auxiliary_statements_values += [instance]
        end
      end

      private

        # Get the class of the join on arel
        def arel_join
          case @join_type
          when :inner then ::Arel::Nodes::InnerJoin
          when :left  then ::Arel::Nodes::OuterJoin
          when :right then ::Arel::Nodes::RightOuterJoin
          when :full  then ::Arel::Nodes::FullOuterJoin
          else
            raise ArgumentError, <<-MSG.strip
              The '#{@join_type}' is not implemented as a join type.
            MSG
          end
        end

        # Mount the query base on it's class
        def mount_query
          klass = self.class
          query = klass.query
          args = @args

          # Call a proc to get the query
          if query.methods.include?(:call)
            call_args = query.try(:arity) === 0 ? [] : [OpenStruct.new(args)]
            query = query.call(*call_args)
            args = []
          end

          # Prepare the query depending on its type
          if query.is_a?(String)
            args = args.map{ |k, v| [k, klass.parent.connection.quote(v)] }.to_h
            ::Arel.sql("(#{query})" % args)
          elsif relation_query?(query)
            query.select(*select_columns).arel
          else
            raise ArgumentError, <<-MSG.strip
              Only String and ActiveRecord::Base objects are accepted as query objects,
              #{query.class.name} given for #{self.class.name}.
            MSG
          end
        end

        # Mount the list of join attributes with the additional ones
        def join_columns
          join_attributes + @join.map do |left, right|
            if right.is_a?(Symbol)
              project(left, base_table).eq(project(right))
            else
              project(left).eq(right)
            end
          end
        end

        # Mount the list of selected attributes with the additional ones
        def select_columns
          selected_attributes + @select.map do |left, right|
            project(left, query_table).as(right.to_s)
          end + @join.map do |left, right|
            column = right.is_a?(Symbol) ? right : left
            project(column, query_table)
          end
        end

    end
  end
end
