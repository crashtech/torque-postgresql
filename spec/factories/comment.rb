FactoryGirl.define do
  factory :comment do
    content { Faker::Lorem.paragraph }

    factory :comment_recursive do
      comment_id { Comment.order('RANDOM()').first.id }
    end

    trait :random_user do
      user_id { User.order('RANDOM()').first.id }
    end
  end
end
