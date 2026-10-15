require "rails_helper"

RSpec.describe "Projects" do
  let(:project) { create(:project) }

  it "shows every project page, with runs in the history" do
    sign_in
    project.command_runs.create!(kind: "version")
    project.console_sessions.create!(kind: "rails")

    [ project_path(project), project_commands_path(project), project_command_runs_path(project),
      project_monitoring_path(project), project_proxy_path(project), project_config_path(project) ].each do |path|
      get path
      expect(response).to have_http_status(:ok), path
    end

    get root_path
    expect(response).to have_http_status(:ok)
  end

  it "shows apps deployed outside Kamal Web as live on the dashboard" do
    sign_in
    project = create(:project, name: "shop", config_snapshots: { "" => { "service" => "shop", "roles" => { "web" => [ "192.0.2.10" ] } } })

    get root_path
    expect(response.body).to include("never deployed", "Ready for your first deploy")

    project.server_metrics.create!(host: "192.0.2.10", collected_at: Time.current, containers: [
      { "Names" => "shop-web-abc123", "State" => "running", "CreatedAt" => 2.hours.ago.utc.strftime("%F %T +0000 UTC"), "Labels" => { "service" => "shop", "role" => "web", "destination" => "" } }
    ])

    get root_path
    expect(response.body).to include("abc123", "live", "about 2 hours")
    expect(response.body).not_to include("never deployed", "Ready for your first deploy")
  end

  it "creates a project and attempts a first sync" do
    sign_in
    allow_any_instance_of(ProjectWorkspace).to receive(:sync!).and_return(true)

    post projects_path, params: { project: { name: "shop", source_kind: "git", repository_url: "https://github.com/acme/shop.git", branch: "main", config_file: "config/deploy.yml" } }

    expect(response).to redirect_to(project_path(Project.last))
    expect(Project.last.name).to eq("shop")
  end

  it "keeps stored secrets when the fields are left empty" do
    project.update!(ssh_private_key: "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----")
    sign_in
    allow_any_instance_of(ProjectWorkspace).to receive(:sync!).and_return(true)

    patch project_path(project), params: { project: { name: "renamed", ssh_private_key: "" } }

    expect(project.reload.name).to eq("renamed")
    expect(project.ssh_private_key).to include("abc")
  end

  it "never renders stored secrets back" do
    project.update!(git_access_token: "ghp_dont_show_me")
    project.environment_variables.create!(key: "REGISTRY", value: "hunter2hunter2")
    sign_in

    get edit_project_path(project)
    expect(response.body).not_to include("ghp_dont_show_me")

    get project_settings_path(project)
    expect(response.body).not_to include("hunter2hunter2")
  end

  it "offers a rollback for every version still on the server" do
    sign_in
    release = ServerReleases::Release
    allow_any_instance_of(ServerReleases).to receive(:call).and_return([
      release.new(version: "b" * 40, state: "running", created_at: 1.hour.ago, current: true),
      release.new(version: "a" * 40, state: "exited", created_at: 1.day.ago, current: false)
    ])

    get project_releases_path(project), headers: { "Turbo-Frame" => "releases" }

    expect(response.body).to include("live", "aaaaaaa")
    expect(response.body.scan("Roll back</button>").size).to eq(1)
  end

  it "explains why detected apps can't roll back" do
    sign_in
    project.update!(source_kind: "discovered", repository_url: nil, discovered_service: "demo", discovered_files: "{}")
    allow_any_instance_of(ServerReleases).to receive(:call).and_return([
      ServerReleases::Release.new(version: "v2", state: "running", created_at: nil, current: true),
      ServerReleases::Release.new(version: "v1", state: "exited", created_at: nil, current: false)
    ])

    get project_releases_path(project)

    expect(response.body).not_to include("Roll back</button>")
    expect(CGI.unescapeHTML(response.body)).to include("needs the app's repository")
  end

  it "charts the proxy traffic of this app only" do
    sign_in
    request = ->(service, status) { ProxyInspector::Request.new(time: 1.minute.ago, host: "x", path: "/", method: "GET", status: status, duration_ms: 3.0, service: service, remote_addr: nil) }
    inspector = instance_double(ProxyInspector, routes: [], requests: [ request.("demo-web", 200), request.("demo-web", 503), request.("other-web", 200) ])
    allow(ProxyInspector).to receive(:new).and_return(inspector)

    get project_proxy_path(project), headers: { "Turbo-Frame" => "proxy_data" }

    expect(response.body).to include("<svg", "Requests (1 h)")
    expect(response.body).to match(%r{Requests \(1 h\)</p>\s*<p[^>]*>2</p>})
  end

  it "explains that apps deployed from the terminal are added automatically" do
    sign_in
    get new_project_path
    expect(response.body).to include("Prefer deploying from your terminal?", discovery_path)
  end
end
