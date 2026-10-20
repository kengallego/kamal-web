require "rails_helper"
require "net/ssh"

RSpec.describe SshHostKeys do
  let(:home) { Dir.mktmpdir("kamal-web-home") }
  let(:public_key) do
    Dir.mktmpdir do |dir|
      system("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", File.join(dir, "key"), exception: true)
      File.read(File.join(dir, "key.pub")).split.first(2).join(" ")
    end
  end
  let(:fingerprint) { IO.popen([ "ssh-keygen", "-l", "-f", "-" ], "r+") { |io| io.write(public_key); io.close_write; io.read }[/SHA256:\S+/] }

  before { allow(Dir).to receive(:home).and_return(home) }
  after { FileUtils.rm_rf(home) }

  it "trusts new hosts on first use, or only trusted ones in strict mode" do
    expect([ described_class.checking, described_class.net_ssh_verify ]).to eq([ "accept-new", :accept_new ])

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("KAMAL_WEB_SSH_HOST_KEYS").and_return("strict")
    expect([ described_class.checking, described_class.net_ssh_verify ]).to eq([ "yes", :always ])
  end

  it "points Kamal's net-ssh at the same setting and known_hosts, without overwriting a hand-written config" do
    described_class.write_config!
    config = File.read(File.join(home, ".ssh/config"))
    expect(config).to include("StrictHostKeyChecking accept-new", "UserKnownHostsFile #{home}/.ssh/known_hosts")
    expect(Net::SSH.configuration_for("192.0.2.10", File.join(home, ".ssh/config"))).to include(verify_host_key: :accept_new)

    File.write(File.join(home, ".ssh/config"), "Host *\n  User deploy\n")
    described_class.write_config!
    expect(File.read(File.join(home, ".ssh/config"))).to eq("Host *\n  User deploy\n")
  end

  it "trusts a scanned key only if the server still offers it, and forgets it" do
    allow(described_class).to receive(:scan).with("192.0.2.10", 2222).and_return([ SshHostKeys::Key.new(type: "ED25519", fingerprint: fingerprint, line: "[192.0.2.10]:2222 #{public_key}") ])

    expect(described_class.trust!("192.0.2.10", 2222, "SHA256:something-else")).to be(false)
    expect(described_class.trusted("192.0.2.10", 2222)).to be_empty

    expect(described_class.trust!("192.0.2.10", 2222, fingerprint)).to be(true)
    expect(described_class.trusted("192.0.2.10", 2222)).to eq([ SshHostKeys::Key.new(type: "ED25519", fingerprint: fingerprint, line: nil) ])
    expect(described_class.trusted("192.0.2.10", 22)).to be_empty

    described_class.forget!("192.0.2.10", 2222)
    expect(described_class.trusted("192.0.2.10", 2222)).to be_empty
  end

  it "makes every ssh Kamal Web starts use them" do
    expect(File.read(File.join(SshWrapper.directory, "ssh"))).to include("-o StrictHostKeyChecking=accept-new", "-o UserKnownHostsFile=")
    expect(RemoteShell.allocate.tap { |shell| shell.send(:connect_as, "192.0.2.10", user: "root", port: 22, keys: []) }.send(:options)).to include(verify_host_key: :accept_new, user_known_hosts_file: "#{home}/.ssh/known_hosts")
  end
end
