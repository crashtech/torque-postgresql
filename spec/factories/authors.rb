FactoryBot.define do
  factory :author do
    name      { Faker::Name.name }
    specialty { Enum::Specialties.values.sample }
  end
end
