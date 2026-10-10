require "rails_helper"

RSpec.describe ServerReleases do
  let(:project) do
    create(:project, config_snapshots: {
      "staging" => { "service" => "shop", "primary_role" => "web", "roles" => { "web" => [ "192.0.2.10" ], "job" => [ "192.0.2.11" ] }, "accessories" => {} }
    })
  end

  subject(:releases) { described_class.new(project, "staging") }

  it "lists the versions kept on the primary host, newest first, marking the live one" do
    output = <<~OUT
      shop-web-staging-aaa111\texited\t2026-10-10 10:00:00 +0000 UTC
      shop-web-staging-ccc333\trunning\t2026-10-12 10:00:00 +0000 UTC
      shop-web-staging-bbb222_replaced_1a2b3c\texited\t2026-10-11 10:00:00 +0000 UTC
      shop-web-staging-bbb222\texited\t2026-10-11 09:00:00 +0000 UTC
    OUT
    shell = instance_double(RemoteShell, run: output)
    expect(RemoteShell).to receive(:new).with(project, "192.0.2.10", destination: "staging").and_return(shell)

    list = releases.call

    expect(list.map(&:version)).to eq(%w[ ccc333 bbb222 aaa111 ])
    expect(list.map(&:current)).to eq([ true, false, false ])
  end

  it "filters by the app's labels without letting the config inject shell" do
    expect(releases.command).to include("--filter label=service=shop --filter label=role=web --filter label=destination=staging")

    project.update!(config_snapshots: { "" => { "service" => "shop;rm -rf /", "roles" => { "web" => [ "192.0.2.10" ] } } })
    expect { described_class.new(project, nil).command }.to raise_error(RemoteShell::Error)
  end
end
