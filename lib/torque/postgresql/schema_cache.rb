module Torque
  module PostgreSQL
    module SchemaCache

      def initialize(conn)
        super
        @data_types = {}
      end

      def initialize_dup(other)
        super
        @data_types = @data_types.dup
      end

      # A cached lookup for data types existence.
      def data_type_exists?(name)
        prepare_data_types if @data_types.empty?
        return @data_types[name] if @data_types.key? name

        @data_types[name] = connection.data_type_exists?(name)
      end

      # Add internal cache for type with +type_name+.
      def add_type(type_name)
        if data_type_exists?(type_name)
          columns("type::#{type_name}")
          columns_hash("type::#{type_name}")
        end
      end

      def data_types(name)
        @data_types[name]
      end

      # Get the columns for a table or a type
      def columns(name, from_type = false)
        return super(name) unless from_type
        @columns["type::#{name}"] ||= connection.composite_columns(name)
      end

      # Get the columns for a table or a type as a hash, key is the column name
      # value is the column object.
      def columns_hash(name, from_type = false)
        return super(name) unless from_type
        @columns_hash["type::#{name}"] ||= Hash[columns(name, true).map { |col|
          [col.name, col]
        }]
      end

      # Clears out internal caches
      def clear!
        super
        @data_types.clear
      end

      def size
        super + @data_types.map(&:size).inject(:+)
      end

      # Clear out internal caches for +name+.
      def clear_data_source_cache!(name, from_type = false)
        return super(name) unless from_type
        @columns.delete "type::#{name}"
        @columns_hash.delete "type::#{name}"
        @data_types.delete name
      end

      def marshal_dump
        super << @data_types
      end

      def marshal_load(array)
        @data_types = array.pop
        super
      end

      private

        def prepare_data_types
          connection.user_defined_types.each do |type|
            @data_types[type['name']] = type['type']
          end
        end

    end

    ActiveRecord::ConnectionAdapters::SchemaCache.prepend SchemaCache
  end
end
