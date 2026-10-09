require "rails_helper"

RSpec.describe DeployNotificationJob do
  let(:project) { create(:project, name: "shop", notification_webhook_url: "https://hooks.example.com/x") }
  let(:run) do
    project.command_runs.create!(kind: "deploy", user: create(:user, name: "Ada"), git_revision: "abcdef1234").tap do |run|
      run.update_columns(status: "succeeded", exit_code: 0)
    end
  end

  it "formats Slack and Discord messages" do
    project.update!(notification_format: "slack")
    expect(described_class.new.payload(run)[:text]).to include("Deploy succeeded for shop", "abcdef1", "Ada")

    project.update!(notification_format: "discord")
    expect(described_class.new.payload(run)[:content]).to include("Deploy succeeded")
  end

  it "sends structured JSON by default" do
    expect(described_class.new.payload(run)).to include(event: "command_run.finished", project: "shop", status: "succeeded", command: "deploy")
  end
end
