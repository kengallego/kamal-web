require "rails_helper"

RSpec.describe ProjectChecks do
  let(:project) do
    create(:project, synced_at: 1.minute.ago, config_snapshots: {
      "" => { "service" => "shop", "primary_role" => "web", "roles" => { "web" => [ "192.0.2.10" ] }, "accessories" => { "db" => [ "192.0.2.20" ] } }
    })
  end

  def metric(host, error: nil, containers: [])
    project.server_metrics.create!(host: host, collected_at: 30.seconds.ago, error: error, containers: containers.map { |name| { "Names" => name } })
  end

  def check(checks, label) = checks.find { |c| c.label == label }

  it "passes when SSH works, kamal-proxy and the app run and the secrets are set" do
    FileUtils.mkdir_p(project.workspace_path.join(".kamal"))
    project.workspace_path.join(".kamal/secrets").write("# KAMAL_IGNORED=$NOT_THIS\nKAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD\n")
    project.environment_variables.create!(key: "KAMAL_REGISTRY_PASSWORD", value: "x")
    metrics = { "192.0.2.10" => metric("192.0.2.10", containers: %w[ kamal-proxy shop-web-abc123 ]), "192.0.2.20" => metric("192.0.2.20") }

    checks = described_class.new(project, nil, metrics).all

    expect(checks.map(&:label)).to eq([ "Config", "SSH to 192.0.2.10", "SSH to 192.0.2.20", "kamal-proxy", "App", "Secrets" ])
    expect(checks).to all(be_ok)
  ensure
    FileUtils.rm_rf(project.workspace_path)
  end

  it "says what is wrong and how to fix it" do
    FileUtils.mkdir_p(project.workspace_path.join(".kamal"))
    project.workspace_path.join(".kamal/secrets").write("RAILS_MASTER_KEY=$RAILS_MASTER_KEY\n")
    metrics = { "192.0.2.10" => metric("192.0.2.10", containers: %w[ other-web-1 ]), "192.0.2.20" => metric("192.0.2.20", error: "Permission denied (publickey)") }

    checks = described_class.new(project, nil, metrics).all

    expect(check(checks, "SSH to 192.0.2.20").detail).to include("Permission denied")
    expect(check(checks, "kamal-proxy").detail).to include("Boot proxy")
    expect(check(checks, "App").detail).to include("No web container")
    expect(check(checks, "Secrets").detail).to include("RAILS_MASTER_KEY isn't set")
    expect(checks.count(&:failed?)).to eq(4)
  ensure
    FileUtils.rm_rf(project.workspace_path)
  end

  it "doesn't guess before the first monitoring sample" do
    checks = described_class.new(project, nil, {}).all

    expect(check(checks, "SSH to 192.0.2.10").status).to eq(:unknown)
    expect(check(checks, "App")).to be_nil
  end
end
