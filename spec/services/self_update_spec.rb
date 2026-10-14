require "rails_helper"

RSpec.describe SelfUpdate do
  let(:container) do
    {
      "Config" => { "Image" => "localhost:5555/kamal-web:abc123" },
      "NetworkSettings" => { "Networks" => { "kamal" => {} } },
      "Mounts" => [
        { "Type" => "volume", "Name" => "kamal_web_storage", "Destination" => "/rails/storage" },
        { "Type" => "bind", "Source" => "/var/run/docker.sock", "Destination" => "/var/run/docker.sock" }
      ]
    }
  end
  let(:docker) { instance_double(LocalDocker, container: container) }
  let(:instance_env) do
    { "KAMAL_CONTAINER_NAME" => "kamal-web-web-abc123", "KAMAL_WEB_URL" => "https://kamal.example.com",
      "KAMAL_WEB_PASSWORD" => "a long password", "KAMAL_WEB_SSH_USER" => "deploy" }
  end

  around do |example|
    previous = ENV.to_h.slice(*instance_env.keys)
    ENV.update(instance_env)
    example.run
  ensure
    instance_env.each_key { |name| ENV.delete(name) }
    ENV.update(previous)
  end

  it "starts a helper container like this one, with the settings off the command line" do
    expect(docker).to receive(:start_container) do |*args, env:|
      expect(args.each_cons(2).to_a).to include([ "--network", "kamal" ], [ "--volume", "kamal_web_storage:/rails/storage" ], [ "--volume", "/var/run/docker.sock:/var/run/docker.sock" ], [ "--env", "KAMAL_WEB_PASSWORD" ])
      expect(args.last(3)).to eq([ "localhost:5555/kamal-web:abc123", "./bin/rails", "kamal_web:self_update[v9.0.0]" ])
      expect(args.join(" ")).not_to include("a long password")
      expect(env).to include("KAMAL_WEB_PASSWORD" => "a long password", "KAMAL_WEB_URL" => "https://kamal.example.com")
      "helper-id"
    end

    expect(described_class.new(docker: docker).launch("v9.0.0")).to be(true)
    expect(Setting.instance).to have_attributes(auto_update_version: "9.0.0", auto_update_status: "running", auto_update_running?: true)
  end

  it "records a helper that doesn't start" do
    allow(docker).to receive(:start_container).and_raise(LocalDocker::Error, "Conflict. The container name is already in use")

    expect(described_class.new(docker: docker).launch("v9.0.0")).to be(false)
    expect(Setting.instance).to have_attributes(auto_update_status: "failed", auto_update_output: include("already in use"))
  end

  it "won't run outside the container Kamal deployed, or with volumes the release doesn't mount" do
    expect(described_class.new(docker: instance_double(LocalDocker, container: nil)).problem).to eq([ :not_deployed, {} ])

    container["Mounts"] << { "Type" => "bind", "Source" => "/srv/projects", "Destination" => "/projects" }
    self_update = described_class.new(docker: docker)
    expect(self_update.problem).to eq([ :custom_volumes, { paths: "/projects" } ])
    expect(docker).not_to receive(:start_container)
    expect(self_update.launch("v9.0.0")).to be(false)
  end

  describe "#perform" do
    let(:self_update) { described_class.new(docker: docker) }
    let(:commands) { [] }

    before do
      allow(SshAgent).to receive(:with_keys).and_yield({ "SSH_AUTH_SOCK" => "/tmp/agent.sock" })
      allow(KamalDiscovery).to receive(:host_address).and_return("172.18.0.1")
    end

    it "deploys the release image with the release's config and this instance's settings" do
      allow(Open3).to receive(:capture2e) do |env, *command, **|
        commands << command
        expect(env).to include("KAMAL_WEB_SERVER" => "172.18.0.1", "KAMAL_WEB_HOST" => "kamal.example.com", "KAMAL_WEB_SSH_USER" => "deploy", "KAMAL_WEB_PASSWORD" => "a long password")
        expect(env["SSH_AUTH_SOCK"]).to eq("/tmp/agent.sock")
        [ "ok\n", instance_double(Process::Status, success?: true) ]
      end

      self_update.perform("v9.0.0")

      kamal = [ RbConfig.ruby, "-rbundler/setup", Rails.root.join(SelfUpdate::LAUNCHER).to_s ]
      expect(commands.map { |command| command.first(2) }).to eq([ %w[ git clone ], %w[ docker pull ], %w[ docker tag ], kamal.first(2), %w[ docker push ], kamal.first(2) ])
      expect(commands[2].last(2)).to eq([ "ghcr.io/kengallego/kamal-web:v9.0.0", "localhost:5555/kamal-web:v9.0.0" ])
      expect(commands[3]).to eq([ *kamal, "registry", "setup" ])
      expect(commands[5]).to eq([ *kamal, "deploy", "--skip-push", "--version", "v9.0.0" ])
      expect(Setting.instance).to have_attributes(auto_update_status: "succeeded", auto_update_output: include("ok"))
    end

    it "stops at the first failing step and keeps its output" do
      allow(Open3).to receive(:capture2e).and_return([ "manifest unknown\n", instance_double(Process::Status, success?: false) ])

      self_update.perform("v9.0.0")

      expect(Open3).to have_received(:capture2e).once
      expect(Setting.instance).to have_attributes(auto_update_status: "failed", auto_update_output: include("manifest unknown"))
    end
  end
end
