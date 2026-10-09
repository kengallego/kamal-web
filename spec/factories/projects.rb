FactoryBot.define do
  factory :project do
    sequence(:name) { |n| "project-#{n}" }
    source_kind { "git" }
    repository_url { "https://github.com/acme/demo.git" }
    branch { "main" }
    config_snapshots { { "" => { "service" => "demo", "roles" => { "web" => [ "192.0.2.10" ] }, "accessories" => {} } } }
  end
end
