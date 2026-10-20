FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "Person #{n}" }
    sequence(:email_address) { |n| "person#{n}@example.com" }
    password { AuthenticationHelpers::PASSWORD }
  end
end
