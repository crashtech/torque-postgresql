module Torque
  module PostgreSQL
    module SchemaDumper

      def extensions(stream)
        super
        user_defined_types(stream)
      end

      private

        def user_defined_types(stream)
          types = @connection.user_defined_types
          return unless types.any?

          stream.puts "  # These are user-defined types used on this database"
          types.each do |name, type|
            raise StandardError, "User-defined type '#{name}' cannot be dumped!" if type.blank?
            send(type.to_sym, name, stream)
          end
          stream.puts
        rescue => e
          stream.puts "# Could not dump user-defined types because of following #{e.class}"
          stream.puts "#   #{e.message}"
          stream.puts
        end

        def enum(name, stream)
          values = @connection.enum_values(name).map { |v| "\"#{v}\"" }
          stream.puts "  create_enum \"#{name}\", [#{values.join(', ')}], force: :cascade"
        end

    end

    ActiveRecord::SchemaDumper.prepend SchemaDumper
  end
end
