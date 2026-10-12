require "rails_helper"

RSpec.describe DeployPreview do
  let(:project) { create(:project) }

  it "reads Kamal's deploy lock" do
    preview = described_class.new(project, nil)

    expect(preview.lock_command).to include(".kamal/lock-demo")
    expect(preview.parse_lock("")).to be_nil
    expect(preview.parse_lock("locked\nLocked by: Ken at 2026-10-16T10:00:00Z\nMessage: migrating\n").details).to eq("Locked by: Ken at 2026-10-16T10:00:00Z\nMessage: migrating")
  end

  it "lists the commits since the live version" do
    Dir.mktmpdir do |dir|
      allow(project).to receive(:workspace_path).and_return(Pathname.new(dir))
      git = ->(*args) { system("git", "-C", dir, "-c", "user.name=Test", "-c", "user.email=test@example.com", *args, out: File::NULL, err: File::NULL, exception: true) }
      git.("init", "-q")
      %w[ first second third ].each { |message| git.("commit", "-q", "--allow-empty", "-m", message) }
      live = `git -C #{dir} rev-parse HEAD~2`.strip

      shell = instance_double(RemoteShell, run: "#{DeployPreview::SEPARATOR}\ndemo-web-#{live}\trunning\t2026-10-16 10:00:00 +0000 UTC\n")
      allow(RemoteShell).to receive(:new).and_return(shell)

      preview = described_class.new(project, nil).call
      expect(preview.lock).to be_nil
      expect(preview.state).to eq(:ahead)
      expect(preview.commits.map(&:subject)).to eq(%w[ third second ])

      allow(shell).to receive(:run).and_return("#{DeployPreview::SEPARATOR}\ndemo-web-#{"f" * 40}\trunning\t2026-10-16 10:00:00 +0000 UTC\n")
      expect(described_class.new(project, nil).call.state).to eq(:unknown)
    end
  end
end
