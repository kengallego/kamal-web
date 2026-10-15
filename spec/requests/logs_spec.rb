require "rails_helper"

RSpec.describe "Logs" do
  let(:project) { create(:project) }

  before { sign_in }

  it "opens with the default options and follow live checked" do
    get project_logs_path(project)

    expect(response.body).to include('id="log_host"', "192.0.2.10", 'name="options[lines]"', 'value="200"', 'turbo-frame id="log_output"')
    expect(response.body).to match(/id="log_follow"[^>]*checked="checked"/)
  end

  it "fills the options from the link that opened it" do
    get project_logs_path(project, options: { host: "192.0.2.10", container_id: "demo-web-abc" })

    expect(response.body).to include('<option selected="selected" value="192.0.2.10">', 'value="demo-web-abc"')
  end

  it "runs the logs into the frame and stops the run it replaces" do
    expect {
      post project_logs_path(project), params: { options: { lines: "50", grep: "", follow: "1" } }
    }.to have_enqueued_job(CommandRunJob)

    first = CommandRun.last
    expect(first).to have_attributes(kind: "app_logs", options: include("lines" => "50", "follow" => "1"))
    expect(response.body).to include('turbo-frame id="log_output"', "run_output_#{first.id}", "Stop following")

    post project_logs_path(project), params: { replace: first.id, options: { follow: "0" } }
    expect(first.reload.status).to eq("canceled")
    expect(CommandRun.last).not_to be_follow
  end

  it "shows why the logs could not run" do
    post project_logs_path(project), params: { options: { grep: "it's" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("quotes")
  end

  it "is a tab of its own instead of a command" do
    get project_commands_path(project)

    expect(response.body).to include(project_logs_path(project))
    expect(response.body).not_to include('value="app_logs"', 'value="app_exec"', 'value="rails_runner"')
  end
end
