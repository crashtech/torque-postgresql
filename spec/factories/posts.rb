FactoryBot.define do
  factory :post do
    title   { Faker::Lorem.sentence }
    content { Faker::Lorem.paragraph }
  end
end
