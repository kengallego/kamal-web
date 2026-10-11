require "rails_helper"

RSpec.describe "Discovered projects" do
  let(:project) do
    create(:project, name: "shop", source_kind: "discovered", repository_url: nil, discovered_service: "shop",
      discovered_files: { "config/deploy.yml" => "service: shop\n" }.to_json)
  end

  it "scans the server" do
    sign_in
    result = KamalDiscovery::Result.new(apps: [ :shop ], created: [ project ], updated: [], error: nil)
    allow(KamalDiscovery).to receive(:new).and_return(instance_double(KamalDiscovery, call: result))

    post discovery_path

    expect(flash[:notice]).to eq("Found 1 Kamal app on this server, added shop.")
  end

  it "explains why deploys are unavailable" do
    sign_in

    get project_path(project)
    expect(response.body).to include("Detected on this server")

    get project_commands_path(project)
    expect(CGI.unescapeHTML(response.body)).to include("More commands available with the app's code")
  end

  it "only shows the SSH instructions while the server refuses Kamal Web's key" do
    sign_in

    project.server_metrics.create!(host: "192.0.2.10", collected_at: 2.minutes.ago, error: "Permission denied (publickey)")
    get project_path(project)
    expect(CGI.unescapeHTML(response.body)).to include("can't connect to 192.0.2.10 over SSH", "Permission denied (publickey)")

    project.server_metrics.create!(host: "192.0.2.10", collected_at: 1.minute.ago, cpu_percent: 5)
    get project_path(project)
    expect(response.body).not_to include("over SSH")
    expect(response.body).not_to include("checking SSH access")
  end

  it "becomes a regular project once its repository is connected" do
    sign_in
    allow(ProjectWorkspace).to receive(:new).and_return(instance_double(ProjectWorkspace, sync!: true))

    patch project_path(project), params: { project: { source_kind: "git", repository_url: "git@github.com:acme/shop.git" } }

    expect(project.reload).to be_git
    expect(project.allows_command?(CommandCatalog.find("deploy"))).to be(true)
  end
end
