require "rails_helper"

RSpec.describe KamalDiscovery do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      example.run
    end
  end

  let(:docker) { instance_double(LocalDocker, available?: true, proxy_routes: routes, image_architecture: "arm64", container: proxy_container, read_files: {}) }
  let(:routes) { [ ProxyInspector::Route.new("shop-web", "shop.example.com,www.shop.example.com", "/", "shop-web-abc123:3000", "running", "yes") ] }
  let(:proxy_container) { { "Mounts" => [ { "Source" => "/home/deploy/.kamal/proxy/apps-config" } ] } }
  let(:containers) do
    [
      container("shop-web-abc123", "ghcr.io/acme/shop:abc123", { "service" => "shop", "role" => "web", "destination" => "" }),
      container("shop-web-old999", "ghcr.io/acme/shop:old999", { "service" => "shop", "role" => "web", "destination" => "" }, running: false, created: "2026-01-01T00:00:00Z"),
      container("shop-job-abc123", "ghcr.io/acme/shop:abc123", { "service" => "shop", "role" => "job", "destination" => "" }),
      container("shop-db", "postgres:16", { "service" => "shop-db" }),
      container("blog-web-staging-v2", "acme/blog:v2", { "service" => "blog", "role" => "web", "destination" => "staging" })
    ]
  end

  subject(:discovery) { described_class.new(docker: docker, host_address: "172.18.0.1") }

  before do
    allow(Rails.configuration.x).to receive(:workspaces_path).and_return(Pathname.new(@root))
    allow(docker).to receive(:kamal_containers).and_return(containers)
    allow(ProjectWorkspace).to receive(:new).and_return(instance_double(ProjectWorkspace, sync!: true))
  end

  def container(name, image, labels, running: true, created: "2026-10-01T00:00:00Z")
    { "Id" => SecureRandom.hex(32), "Name" => "/#{name}", "Created" => created, "State" => { "Running" => running },
      "Config" => { "Image" => image, "Labels" => labels, "WorkingDir" => "/rails" }, "Mounts" => [] }
  end

  it "rebuilds a config from the running containers and proxy routes" do
    shop = discovery.discover.find { |app| app.service == "shop" }
    config = YAML.safe_load(shop.files["config/deploy.yml"])

    expect(shop.config_source).to eq("generated")
    expect(shop.versions).to eq("" => "abc123")
    expect(config).to include(
      "service" => "shop", "image" => "acme/shop",
      "registry" => { "server" => "ghcr.io", "username" => "kamal-web", "password" => [ "KAMAL_REGISTRY_PASSWORD" ] },
      "builder" => { "arch" => "arm64" }, "ssh" => { "user" => "deploy" },
      "servers" => { "web" => { "hosts" => [ "172.18.0.1" ] }, "job" => { "hosts" => [ "172.18.0.1" ] } },
      "proxy" => { "hosts" => [ "shop.example.com", "www.shop.example.com" ], "ssl" => true, "app_port" => 3000 },
      "accessories" => { "db" => { "image" => "postgres:16", "host" => "172.18.0.1" } }
    )
  end

  it "never lists Kamal Web itself, including its older versions" do
    containers.push(
      container("kamal-web-web-v2", "kamal-web:v2", { "service" => "kamal-web", "role" => "web", "destination" => "" }),
      container("kamal-web-web-v1", "kamal-web:v1", { "service" => "kamal-web", "role" => "web", "destination" => "" }, running: false)
    )
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("KAMAL_CONTAINER_NAME").and_return("kamal-web-web-v2")

    expect(discovery.discover.map(&:service)).to contain_exactly("shop", "blog")
  end

  it "puts destinations in their own files" do
    blog = discovery.discover.find { |app| app.service == "blog" }

    expect(blog.versions).to eq("staging" => "v2")
    expect(YAML.safe_load(blog.files["config/deploy.yml"])).to include("image" => "acme/blog", "registry" => hash_excluding("server"))
    expect(YAML.safe_load(blog.files["config/deploy.staging.yml"])).to eq("servers" => { "web" => { "hosts" => [ "172.18.0.1" ] } })
  end

  it "prefers the deploy.yml shipped in the image and keeps only secret names" do
    allow(docker).to receive(:read_files) do |_, path|
      if path == "/rails/config"
        { "config/deploy.yml" => "service: shop\nimage: acme/shop\n", "config/deploy.production.yml" => "servers: [1.2.3.4]\n", "config/database.yml" => "x" }
      else
        { ".kamal/secrets" => "KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD\nRAILS_MASTER_KEY=$(cat config/master.key)\n", ".kamal/hooks/pre-deploy" => "rm -rf /" }
      end
    end

    shop = discovery.discover.find { |app| app.service == "shop" }

    expect(shop.config_source).to eq("image")
    expect(shop.files.keys).to contain_exactly("config/deploy.yml", "config/deploy.production.yml", ".kamal/secrets")
    expect(shop.files[".kamal/secrets"]).to eq("KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD\nRAILS_MASTER_KEY=$RAILS_MASTER_KEY\n")
  end

  it "adds new apps once, updates them, and respects removed or managed ones" do
    result = discovery.call
    expect(result.created.map(&:name)).to contain_exactly("shop", "blog")

    shop = Project.find_by!(discovered_service: "shop")
    expect(shop).to be_discovered
    expect(shop.environment_for(nil)).to include("VERSION" => "abc123")
    expect(discovery.call.created).to be_empty

    Project.find_by!(discovered_service: "blog").destroy
    expect(discovery.call.created).to be_empty

    Setting.instance.update!(ignored_services: [])
    create(:project, name: "blog-from-git", config_snapshots: { "staging" => { "service" => "blog" } })
    expect(discovery.call.created).to be_empty
  end

  it "keeps discovered projects to commands that don't need env or secrets" do
    discovery.call
    shop = Project.find_by!(discovered_service: "shop")

    expect(shop.command_runs.new(kind: "deploy").valid?).to be(false)
    expect(shop.command_runs.new(kind: "app_logs").valid?).to be(true)
    expect(shop.command_runs.new(kind: "app_stop").valid?).to be(true)
  end

  it "reports when Docker is unreachable" do
    allow(docker).to receive(:available?).and_return(false)

    expect(discovery.call.error).to include("docker.sock")
  end
end
