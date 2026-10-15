require "rails_helper"

RSpec.describe Project do
  it "requires a repository for git projects" do
    expect(build(:project, repository_url: nil)).not_to be_valid
  end

  it "only accepts https and ssh repository URLs" do
    expect(build(:project, repository_url: "git@github.com:acme/demo.git")).to be_valid
    expect(build(:project, repository_url: "file:///etc")).not_to be_valid
    expect(build(:project, repository_url: "--upload-pack=touch /tmp/x")).not_to be_valid
  end

  it "keeps local projects inside the projects root" do
    root = Rails.configuration.x.projects_path

    expect(build(:project, source_kind: "local", local_path: root.join("app").to_s)).to be_valid
    expect(build(:project, source_kind: "local", local_path: "/etc")).not_to be_valid
    expect(build(:project, source_kind: "local", local_path: "#{root}/../etc")).not_to be_valid
  end

  it "rejects config files outside the project" do
    expect(build(:project, config_file: "../deploy.yml")).not_to be_valid
    expect(build(:project, config_file: "/etc/deploy.yml")).not_to be_valid
  end

  it "rejects things that aren't private keys" do
    expect(build(:project, ssh_private_key: "ssh-ed25519 AAAA public")).not_to be_valid
  end

  it "encrypts secrets at rest" do
    project = create(:project, git_access_token: "ghp_secret")
    raw = Project.connection.select_value("SELECT git_access_token FROM projects WHERE id = #{project.id}")

    expect(raw).not_to include("ghp_secret")
    expect(project.reload.git_access_token).to eq("ghp_secret")
  end

  it "merges destination variables over base variables" do
    project = create(:project)
    project.environment_variables.create!(key: "TOKEN", value: "base")
    project.environment_variables.create!(key: "ONLY_BASE", value: "1")
    project.environment_variables.create!(key: "TOKEN", value: "staging", destination: "staging")

    expect(project.environment_for(nil)).to eq("TOKEN" => "base", "ONLY_BASE" => "1")
    expect(project.environment_for("staging")).to eq("TOKEN" => "staging", "ONLY_BASE" => "1")
  end

  it "finds the live version of each destination from the latest samples" do
    project = create(:project, config_snapshots: {
      "production" => { "service" => "shop", "roles" => { "web" => [ "192.0.2.10" ] } },
      "staging" => { "service" => "shop", "roles" => { "web" => [ "192.0.2.10" ] } }
    })
    container = ->(name, destination, state, created) { { "Names" => name, "State" => state, "CreatedAt" => created, "Labels" => { "service" => "shop", "role" => "web", "destination" => destination } } }
    project.server_metrics.create!(host: "192.0.2.10", collected_at: Time.current, containers: [
      container.("shop-web-production-abc123", "production", "running", "2026-10-14 13:11:14 +0000 UTC"),
      container.("shop-web-production-old", "production", "exited", "2026-10-10 10:00:00 +0000 UTC"),
      container.("shop-web-staging-def456", "staging", "running", "2026-10-15 09:00:00 +0000 UTC")
    ])

    production = project.live_release("production")
    expect(production.version).to eq("abc123")
    expect(production.created_at).to eq(Time.utc(2026, 10, 14, 13, 11, 14))
    expect(project.live_release("staging").version).to eq("def456")
    expect(project.live_release("production", [])).to be_nil
  end

  it "lists every destination that deploys to a host" do
    project = build(:project, config_snapshots: {
      "production" => { "roles" => { "web" => [ "192.0.2.10" ] } },
      "staging" => { "roles" => { "web" => [ "192.0.2.10" ] }, "accessories" => { "db" => [ "192.0.2.20" ] } }
    })

    expect(project.destinations_for_host("192.0.2.10")).to eq([ "production", "staging" ])
    expect(project.destinations_for_host("192.0.2.20")).to eq([ "staging" ])
    expect(project.destination_for_host("192.0.2.10")).to eq("production")
  end

  it "lists destinations from the config snapshots with the base config as nil" do
    project = build(:project, config_snapshots: { "staging" => {}, "" => {}, "production" => {} })

    expect(project.destinations).to eq([ nil, "production", "staging" ])
  end

  it "generates a long deploy webhook token" do
    expect(create(:project).deploy_webhook_token.length).to be >= 36
  end
end
