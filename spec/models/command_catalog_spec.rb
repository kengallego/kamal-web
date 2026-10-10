require "rails_helper"

RSpec.describe CommandCatalog do
  it "builds argument arrays for each command" do
    expect(described_class.find("deploy").arguments).to eq([ "deploy" ])
    expect(described_class.find("app_logs").arguments("lines" => "50", "grep" => "error")).to eq([ "app", "logs", "--lines", "50", "--grep", "error" ])
    expect(described_class.find("accessory_reboot").arguments({})).to eq([ "accessory", "reboot", "all", "--confirmed" ])
  end

  it "clamps log lines" do
    expect(described_class.find("app_logs").arguments("lines" => "999999")).to eq([ "app", "logs", "--lines", "200" ])
  end

  it "validates rollback versions" do
    rollback = described_class.find("rollback")

    expect(rollback.arguments("version" => "abc123")).to eq([ "rollback", "abc123" ])
    expect { rollback.arguments("version" => "") }.to raise_error(ArgumentError)
    expect { rollback.arguments("version" => "abc; rm -rf /") }.to raise_error(ArgumentError)
  end

  it "shell-escapes Ruby code for the rails runner" do
    arguments = described_class.find("rails_runner").arguments("code" => "puts 'hi'; `id`")

    expect(arguments.last).to eq("bin/rails runner #{Shellwords.escape("puts 'hi'; `id`")}")
  end

  it "marks commands that change servers" do
    expect(described_class.find("deploy")).to be_mutating
    expect(described_class.find("app_logs")).not_to be_mutating
  end

  it "follows logs on a host or container" do
    arguments = described_class.find("app_logs").arguments("host" => "192.0.2.10", "container_id" => "demo-web-abc123", "follow" => "1", "lines" => "50")
    expect(arguments).to eq([ "app", "logs", "--hosts", "192.0.2.10", "--container-id", "demo-web-abc123", "--lines", "50", "--follow" ])
    expect(described_class.find("proxy_logs").arguments("follow" => "0")).not_to include("--follow")
    expect(described_class.find("accessory_logs").arguments("name" => "db", "follow" => "1")).to include("--follow")
  end

  it "rejects log options Kamal would pass to a remote shell" do
    logs = described_class.find("app_logs")
    [ "x' ; id ; '", "a\"b", "$(id)", "`id`", "a\\b" ].each do |grep|
      expect { logs.arguments("grep" => grep) }.to raise_error(ArgumentError), grep
    end
    expect(logs.arguments("grep" => "GET /up [0-9]+")).to include("--grep", "GET /up [0-9]+")
    expect { logs.arguments("container_id" => "abc; id") }.to raise_error(ArgumentError)
    expect { logs.arguments("host" => "-oProxyCommand=id") }.to raise_error(ArgumentError)
  end
end
