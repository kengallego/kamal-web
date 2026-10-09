FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    password { "correct horse battery" }
    role { "deployer" }

    trait :admin do
      role { "admin" }
    end

    trait :viewer do
      role { "viewer" }
    end
  end
end
