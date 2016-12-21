module Torque
  module PostgreSQL
    module Attributes
      module Bindable

        attr_reader :parent, :attribute

        # Bind the currect instance to an model instance and an attribute
        def bind(parent, attribute)
          @parent    = parent
          @attribute = attribute
        end

        # Always bind after cast
        def cast(value)
          super.bind(parent, attribute)
        end

        # Always bind after deserialize
        def deserialize(value)
          super.bind(parent, attribute)
        end

      end
    end
  end
end
