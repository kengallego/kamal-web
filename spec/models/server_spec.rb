require "rails_helper"

RSpec.describe Server do
  it "registers the hosts of a project's config when it changes" do
    project = create(:project, config_snapshots: {
      "" => { "roles" => { "web" => [ "192.0.2.10" ] }, "accessories" => { "db" => [ "192.0.2.12" ] } },
      "staging" => { "roles" => { "web" => [ "192.0.2.20" ] }, "ssh" => { "user" => "deploy", "port" => 2222 } }
    })
    expect(Server.pluck(:host)).to contain_exactly("192.0.2.10", "192.0.2.12", "192.0.2.20")

    project.update!(config_snapshots: { "" => { "roles" => { "web" => [ "192.0.2.10", "192.0.2.30" ] } } })
    expect(Server.count).to eq(4)
  end

  it "takes SSH settings from the config unless overridden" do
    create(:project, config_snapshots: { "staging" => { "roles" => { "web" => [ "192.0.2.20" ] }, "ssh" => { "user" => "deploy", "port" => 2222 } } })
    server = Server.find_by!(host: "192.0.2.20")

    expect([ server.effective_ssh_user, server.effective_ssh_port ]).to eq([ "deploy", 2222 ])
    server.update!(ssh_user: "admin", ssh_port: 22)
    expect([ server.effective_ssh_user, server.effective_ssh_port ]).to eq([ "admin", 22 ])
    expect([ Server.new(host: "192.0.2.99").effective_ssh_user, Server.new(host: "192.0.2.99").effective_ssh_port ]).to eq([ "root", 22 ])
  end

  it "keeps the host of a server in use" do
    create(:project)
    server = Server.find_by!(host: "192.0.2.10")

    expect(server.update(host: "192.0.2.11")).to be(false)
    expect(Server.create(host: "bad host")).not_to be_persisted
  end

  it "records the result of a connection check" do
    server = Server.create!(host: "192.0.2.50")
    allow(RemoteShell).to receive(:for_server).with(server).and_return(instance_double(RemoteShell, run: "Linux 6.8.0 x86_64\nDocker version 27.3.1\n"))

    server.check!
    expect(server.system_info).to eq("Linux 6.8.0 x86_64 · Docker version 27.3.1")
    expect(server.connection.ok).to be(true)

    allow(RemoteShell).to receive(:for_server).and_return(instance_double(RemoteShell).tap { |shell| allow(shell).to receive(:run).and_raise(RemoteShell::Error, "192.0.2.50: Permission denied") })
    server.check!
    expect(server.connection).to have_attributes(ok: false, error: "192.0.2.50: Permission denied")
  end
end
