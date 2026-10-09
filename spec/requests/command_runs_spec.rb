require "rails_helper"

RSpec.describe "Command runs" do
  let(:project) { create(:project) }

  it "lets deployers deploy" do
    sign_in create(:user)

    expect {
      post project_command_runs_path(project), params: { kind: "deploy" }
    }.to have_enqueued_job(CommandRunJob)

    expect(response).to redirect_to(project_command_run_path(project, CommandRun.last))
  end

  it "keeps viewers to read-only commands" do
    sign_in create(:user, :viewer)

    post project_command_runs_path(project), params: { kind: "deploy" }
    expect(CommandRun.count).to eq(0)

    post project_command_runs_path(project), params: { kind: "app_logs", options: { lines: "20" } }
    expect(CommandRun.last.options).to eq("lines" => "20")
  end

  it "keeps admin-only commands for admins" do
    sign_in create(:user)

    post project_command_runs_path(project), params: { kind: "setup" }
    expect(CommandRun.count).to eq(0)
  end

  it "ignores options a command doesn't declare" do
    sign_in create(:user)

    post project_command_runs_path(project), params: { kind: "app_logs", options: { lines: "5", evil: "x" } }
    expect(CommandRun.last.options).to eq("lines" => "5")
  end

  it "rejects unknown commands" do
    sign_in create(:user, :admin)

    post project_command_runs_path(project), params: { kind: "eval" }
    expect(CommandRun.count).to eq(0)
  end

  it "shows a run and cancels it" do
    user = create(:user)
    sign_in user
    run = project.command_runs.create!(kind: "deploy", user: user)

    get project_command_run_path(project, run)
    expect(response).to have_http_status(:ok)

    post cancel_project_command_run_path(project, run)
    expect(run.reload.status).to eq("canceled")
  end
end
