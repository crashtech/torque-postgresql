# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Arel
      Math = Module.new

      def self.build_operations(operations)
        default_alias = :visit_Arel_Nodes_InfixOperation

        operations&.each do |name, operator|
          klass_name = name.to_s.camelize
          next if ::Arel::Nodes.const_defined?(klass_name)

          klass = Class.new(::Arel::Nodes::InfixOperation)
          operator = (-operator).to_sym
          klass.send(:define_method, :initialize) { |*args| super(operator, *args) }

          ::Arel::Nodes.const_set(klass_name, klass)
          visitor = :"visit_Arel_Nodes_#{klass_name}"
          ::Arel::Visitors::PostgreSQL.send(:alias_method, visitor, default_alias)

          # Don't worry about quoting here, if the right side is something that
          # doesn't need quoting, it will leave it as it is
          Math.send(:define_method, klass_name.underscore) { |other| klass.new(self, other) }
        end
      end

      ::Arel::Nodes::Node.include(Math)
      ::Arel::Attribute.include(Math)
    end
  end
end
