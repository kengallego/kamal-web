require "rails_helper"

RSpec.describe "Servers" do
  before { sign_in }

  it "lists the servers of every project" do
    project = create(:project, name: "shop")
    project.server_metrics.create!(host: "192.0.2.10", collected_at: 1.minute.ago, cpu_percent: 42)

    get servers_path

    expect(response.body).to include("192.0.2.10", "shop", "42%", "connected")
  end

  it "shows every destination a project deploys to a server" do
    project = create(:project, name: "shop", config_snapshots: {
      "production" => { "roles" => { "web" => [ "192.0.2.10" ] } },
      "staging" => { "roles" => { "web" => [ "192.0.2.10" ] } }
    })
    server = Server.find_by!(host: "192.0.2.10")

    get servers_path
    expect(response.body).to include("production", "staging")

    get server_path(server)
    expect(response.body).to include(project_path(project), "production", "staging")
  end

  it "adds a server by hand and checks the connection" do
    Setting.instance.ensure_ssh_key!
    allow(RemoteShell).to receive(:for_server).and_return(instance_double(RemoteShell, run: "Linux 6.8.0 x86_64\n"))

    post servers_path, params: { server: { host: " 203.0.113.10 ", name: "Spare", ssh_port: "2222" } }

    server = Server.find_by!(host: "203.0.113.10")
    expect(response).to redirect_to(server_path(server))
    expect(server).to have_attributes(name: "Spare", ssh_port: 2222, system_info: "Linux 6.8.0 x86_64")

    post servers_path, params: { server: { host: "203.0.113.10" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "shows how to authorize the key when the connection fails" do
    Setting.instance.ensure_ssh_key!
    server = Server.create!(host: "203.0.113.10")
    shell = instance_double(RemoteShell)
    allow(shell).to receive(:run).and_raise(RemoteShell::Error, "203.0.113.10: Permission denied (publickey)")
    allow(RemoteShell).to receive(:for_server).and_return(shell)

    post check_server_path(server)
    follow_redirect!

    expect(response.body).to include("Connection failed", "Permission denied (publickey)", Setting.instance.ssh_public_key)
  end

  it "only deletes servers no project deploys to" do
    create(:project)
    in_use = Server.find_by!(host: "192.0.2.10")
    spare = Server.create!(host: "203.0.113.10")

    delete server_path(in_use)
    expect(flash[:alert]).to include("Remove it from deploy.yml")

    delete server_path(spare)
    expect(response).to redirect_to(servers_path)
    expect(Server.pluck(:host)).to eq([ "192.0.2.10" ])
  end

  it "shows the server's key to compare before trusting it, and forgets it" do
    server = Server.create!(host: "192.0.2.20", ssh_port: 2222)
    key = SshHostKeys::Key.new(type: "ED25519", fingerprint: "SHA256:abc", line: nil)
    allow(SshHostKeys).to receive(:trusted).and_return([])
    allow(SshHostKeys).to receive(:scan).with("192.0.2.20", 2222).and_return([ key ])

    get server_path(server, scan: 1)
    expect(response.body).to include("SHA256:abc", "Trust")

    expect(SshHostKeys).to receive(:trust!).with("192.0.2.20", 2222, "SHA256:abc").and_return(true)
    post trust_host_key_server_path(server), params: { fingerprint: "SHA256:abc" }
    expect(flash[:notice]).to eq("Host key trusted.")
    expect(AuditEvent.last).to have_attributes(action: "servers#trust_host_key", subject_id: server.id)

    expect(SshHostKeys).to receive(:forget!).with("192.0.2.20", 2222)
    delete forget_host_key_server_path(server)
    expect(response).to redirect_to(server_path(server))
  end
end
