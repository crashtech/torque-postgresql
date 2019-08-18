FactoryBot.define do
  factory :tag do
    name { Faker::Lorem.sentence }
  end
end
