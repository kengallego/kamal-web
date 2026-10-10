require "rails_helper"

RSpec.describe ServiceContainers do
  let(:project) { create(:project, config_snapshots: { "" => { "service" => "shop", "roles" => { "web" => [ "192.0.2.10", "192.0.2.11" ] } } }) }

  it "reads the app's containers on every host and reports unreachable ones" do
    output = "shop-web-new\tweb\trunning\tUp 5 seconds\t2026-10-15 10:00:05 +0000 UTC\n" \
      "shop-web-old\tweb\texited\tExited (0) 1 second ago\t2026-10-14 10:00:00 +0000 UTC\n"
    allow(RemoteShell).to receive(:new).with(project, "192.0.2.10", destination: nil).and_return(instance_double(RemoteShell, run: output))
    allow(RemoteShell).to receive(:new).with(project, "192.0.2.11", destination: nil).and_return(instance_double(RemoteShell).tap { |shell| allow(shell).to receive(:run).and_raise(RemoteShell::Error, "192.0.2.11: timeout") })

    containers, errors = described_class.new(project, nil).call

    expect(containers.map(&:name)).to eq(%w[ shop-web-new shop-web-old ])
    expect(containers.first).to be_running
    expect(errors).to eq("192.0.2.11" => "192.0.2.11: timeout")
  end
end
