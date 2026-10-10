require "rails_helper"

RSpec.describe "Command runs" do
  let(:project) { create(:project) }

  it "deploys" do
    sign_in

    expect {
      post project_command_runs_path(project), params: { kind: "deploy" }
    }.to have_enqueued_job(CommandRunJob)

    expect(response).to redirect_to(project_command_run_path(project, CommandRun.last))
  end

  it "ignores options a command doesn't declare" do
    sign_in

    post project_command_runs_path(project), params: { kind: "app_logs", options: { lines: "5", evil: "x" } }
    expect(CommandRun.last.options).to eq("lines" => "5")
  end

  it "rejects unknown commands" do
    sign_in

    post project_command_runs_path(project), params: { kind: "eval" }
    expect(CommandRun.count).to eq(0)
  end

  it "shows a run and cancels it" do
    sign_in
    run = project.command_runs.create!(kind: "deploy")

    get project_command_run_path(project, run)
    expect(response).to have_http_status(:ok)

    post cancel_project_command_run_path(project, run)
    expect(run.reload.status).to eq("canceled")
  end

  it "shows the app's containers next to a deploy until it finishes" do
    sign_in
    run = project.command_runs.create!(kind: "deploy")
    allow_any_instance_of(ServiceContainers).to receive(:call).and_return([ [], {} ])

    get project_command_run_path(project, run)
    expect(response.body).to include(project_containers_path(project, destination: nil, run_id: run.id).sub("&", "&amp;"))

    get project_containers_path(project, run_id: run.id)
    expect(response.body).not_to include("data-poll-final")

    run.update_columns(status: "succeeded")
    get project_containers_path(project, run_id: run.id)
    expect(response.body).to include("data-poll-final")
  end
end
