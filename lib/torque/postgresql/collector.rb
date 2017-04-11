module Torque
  module PostgreSQL
    module Collector

      def self.new(*args)
        klass = Class.new

        args.flatten!
        args.compact!

        klass.module_eval do
          args.each do |attribute|
            define_method attribute do |*args|
              if args.empty?
                instance_variable_get("@#{attribute}")
              elsif args.size > 1
                instance_variable_set("@#{attribute}", args)
              else
                instance_variable_set("@#{attribute}", args.first)
              end
            end
            alias_method "#{attribute}=", attribute
          end
        end

        klass
      end

    end
  end
end
