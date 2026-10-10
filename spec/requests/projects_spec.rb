require "rails_helper"

RSpec.describe "Projects" do
  let(:project) { create(:project) }

  it "shows every project page, with runs in the history" do
    sign_in
    project.command_runs.create!(kind: "version")
    project.console_sessions.create!(kind: "rails")

    [ project_path(project), project_commands_path(project), project_command_runs_path(project),
      project_monitoring_path(project), project_proxy_path(project), project_config_path(project) ].each do |path|
      get path
      expect(response).to have_http_status(:ok), path
    end

    get root_path
    expect(response).to have_http_status(:ok)
  end

  it "creates a project and attempts a first sync" do
    sign_in
    allow_any_instance_of(ProjectWorkspace).to receive(:sync!).and_return(true)

    post projects_path, params: { project: { name: "shop", source_kind: "git", repository_url: "https://github.com/acme/shop.git", branch: "main", config_file: "config/deploy.yml" } }

    expect(response).to redirect_to(project_path(Project.last))
    expect(Project.last.name).to eq("shop")
  end

  it "keeps stored secrets when the fields are left empty" do
    project.update!(ssh_private_key: "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----")
    sign_in
    allow_any_instance_of(ProjectWorkspace).to receive(:sync!).and_return(true)

    patch project_path(project), params: { project: { name: "renamed", ssh_private_key: "" } }

    expect(project.reload.name).to eq("renamed")
    expect(project.ssh_private_key).to include("abc")
  end

  it "never renders stored secrets back" do
    project.update!(git_access_token: "ghp_dont_show_me")
    project.environment_variables.create!(key: "REGISTRY", value: "hunter2hunter2")
    sign_in

    get edit_project_path(project)
    expect(response.body).not_to include("ghp_dont_show_me")

    get project_settings_path(project)
    expect(response.body).not_to include("hunter2hunter2")
  end
end
