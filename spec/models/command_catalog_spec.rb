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
end
