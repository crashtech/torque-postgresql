require_relative './nested_struct'
require 'torque/postgresql'
class Nested < ActiveRecord::Base
  attribute :nested, NestedStruct.database_type
end
