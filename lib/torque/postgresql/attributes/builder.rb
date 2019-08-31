require_relative 'builder/enum'
require_relative 'builder/period'

module Torque
  module PostgreSQL
    module Attributes
      module Builder
        def self.include_on(klass, method_name, builder_klass, &block)
          klass.define_singleton_method(method_name) do |*args, **options|
            return unless connection.table_exists?(table_name)

            args.each do |attribute|
              begin
                # Generate methods on self class
                builder = builder_klass.new(self, attribute, options)
                builder.conflicting?
                builder.build

                # Additional settings for the builder
                instance_exec(builder, &block) if block.present?
              rescue Interrupt
                # Not able to build the attribute, maybe pending migrations
              end
            end
          end
        end
      end
    end
  end
end
