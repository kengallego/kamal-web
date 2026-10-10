require "rails_helper"

RSpec.describe CommandRun do
  let(:project) { create(:project, config_snapshots: { "" => {}, "staging" => {} }) }

  it "enqueues itself when created" do
    expect {
      project.command_runs.create!(kind: "deploy")
    }.to have_enqueued_job(CommandRunJob)
  end

  it "appends the destination flag" do
    run = project.command_runs.build(kind: "app_logs", destination: "staging", options: { "lines" => "10" })

    expect(run.arguments).to eq([ "app", "logs", "--lines", "10", "-d", "staging" ])
    expect(run.display_command).to eq("kamal app logs --lines 10 -d staging")
  end

  it "passes a custom config file" do
    project.update!(config_file: "deploy/kamal.yml")

    expect(project.command_runs.build(kind: "deploy").arguments).to eq([ "deploy", "-c", "deploy/kamal.yml" ])
  end

  it "rejects unknown destinations and commands" do
    expect(project.command_runs.build(kind: "deploy", destination: "production")).not_to be_valid
    expect(project.command_runs.build(kind: "rm_rf")).not_to be_valid
  end

  it "rejects invalid options" do
    run = project.command_runs.build(kind: "rollback", options: { "version" => "" })

    expect(run).not_to be_valid
    expect(run.errors.full_messages).to include("Version is required")
  end

  it "allows only one server-changing command per project at a time" do
    project.command_runs.create!(kind: "deploy")

    expect(project.command_runs.build(kind: "rollback", options: { "version" => "abc" })).not_to be_valid
    expect(project.command_runs.build(kind: "app_logs")).to be_valid
  end

  it "records success and failure from the exit code" do
    run = project.command_runs.create!(kind: "version")
    run.start!
    run.finish!(0)
    expect(run.reload.status).to eq("succeeded")

    run = project.command_runs.create!(kind: "version")
    run.start!
    run.finish!(nil)
    expect(run.reload.status).to eq("failed")
  end

  it "does not overwrite a cancellation when the process exits" do
    run = project.command_runs.create!(kind: "deploy")
    run.start!
    run.cancel!
    run.finish!(143)

    expect(run.reload.status).to eq("canceled")
  end

  it "strips ANSI codes from output and caps its size" do
    run = project.command_runs.create!(kind: "version")
    run.append_output("\e[32mok\e[0m\r\n")
    expect(run.reload.output).to eq("ok\n")

    stub_const("CommandRun::OUTPUT_LIMIT", 10)
    run.append_output("x" * 20)
    run.append_output("more")
    expect(run.reload.output).not_to include("more")
  end

  it "marks runs interrupted by a restart as failed" do
    run = project.command_runs.create!(kind: "deploy")
    run.start!

    described_class.interrupt_stale!

    expect(run.reload.status).to eq("failed")
    expect(run.output).to include("Interrupted")
  end

  it "notifies the project webhook when an operation finishes" do
    project.update!(notification_webhook_url: "https://hooks.example.com/x")
    run = project.command_runs.create!(kind: "deploy")
    run.start!

    expect { run.finish!(0) }.to have_enqueued_job(DeployNotificationJob)
  end
end
