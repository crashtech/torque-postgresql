module Torque
  module PostgreSQL
    module Arel
      nodes = ::Arel::Nodes
      inflix = nodes::InfixOperation
      visitors = ::Arel::Visitors::PostgreSQL
      default_alias = :visit_Arel_Nodes_InfixOperation

      Math = Module.new
      INFLIX_OPERATION = {
        'Overlaps'          => :'&&',
        'Contains'          => :'@>',
        'ContainedBy'       => :'<@',
        'HasKey'            => :'?',
        'HasAllKeys'        => :'?&',
        'HasAnyKeys'        => :'?|',
        'StrictlyLeft'      => :'<<',
        'StrictlyRight'     => :'>>',
        'DoesntRightExtend' => :'&<',
        'DoesntLeftExtend'  => :'&>',
        'AdjacentTo'        => :'-|-',
      }.freeze

      INFLIX_OPERATION.each do |operator_name, operator|
        klass = Class.new(inflix)
        klass.send(:define_method, :initialize) { |*args| super(operator, *args) }

        nodes.const_set(operator_name, klass)
        visitors.send(:alias_method, :"visit_Arel_Nodes_#{operator_name}", default_alias)
        Math.send(:define_method, operator_name.underscore) do |other|
          klass.new(self, ::Arel::Nodes.build_quoted(other, self))
        end
      end

      ::Arel::Nodes::Node.include(Math)
      ::Arel::Attribute.include(Math)
    end
  end
end
