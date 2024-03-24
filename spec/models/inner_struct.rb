require 'torque/postgresql'
require_relative './question'
class InnerStruct < Torque::Struct
  attribute :question, Question.database_type
end
