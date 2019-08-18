FactoryBot.define do
  factory :text do
    content { Faker::Lorem.sentence }
  end
end
