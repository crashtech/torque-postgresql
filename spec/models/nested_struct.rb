require 'torque/postgresql'
class NestedStruct < Torque::Struct
  attribute :ary, InnerStruct.database_array_type
end
