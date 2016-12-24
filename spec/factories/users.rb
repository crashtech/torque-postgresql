FactoryGirl.define do
  factory :user do
    name { Faker::Name.name }
    role { 'visitor' }
  end
end
