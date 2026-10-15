require "rails_helper"

RSpec.describe "Translations" do
  let(:project) do
    create(:project, synced_at: 1.minute.ago, config_snapshots: {
      "" => { "service" => "demo", "primary_role" => "web", "roles" => { "web" => [ "192.0.2.10" ] }, "accessories" => { "db" => [ "192.0.2.10" ] }, "proxy_hosts" => [ "demo.example.com" ] }
    })
  end

  before do
    project.command_runs.create!(kind: "deploy").update_columns(status: "succeeded", output: "done")
    project.console_sessions.create!(kind: "rails")
    project.environment_variables.create!(key: "TOKEN", value: "x")
    project.server_metrics.create!(host: "192.0.2.10", collected_at: 1.minute.ago, cpu_percent: 5, containers: [ { "Names" => "kamal-proxy", "State" => "running" } ])
    Setting.instance.update!(status_board_enabled: true)
    allow_any_instance_of(ServerReleases).to receive(:call).and_return([])
    allow_any_instance_of(ServiceContainers).to receive(:call).and_return([ [], {} ])
    allow(ProxyInspector).to receive(:new).and_return(instance_double(ProxyInspector, routes: [], requests: []))
    preview = instance_double(DeployPreview, lock: DeployPreview::Lock.new(details: ""), deployed_version: "abc", state: :ahead,
      commits: [ DeployPreview::Commit.new(sha: "def", author: "Ken", time: 1.hour.ago, subject: "Fix") ])
    allow(DeployPreview).to receive(:new).and_return(double(call: preview))
    project.alerts.create!(kind: "certificate", subject: "demo.example.com", opened_at: 1.hour.ago)
    project.health_checks.create!(url: "https://demo.example.com/up", checked_at: 1.minute.ago, status_code: 200, duration_ms: 12, certificate_expires_at: 40.days.from_now)
  end

  def pages
    run = project.command_runs.first
    [ root_path, new_project_path, project_path(project), edit_project_path(project), project_commands_path(project),
      project_command_runs_path(project), project_command_run_path(project, run), project_console_sessions_path(project),
      project_console_session_path(project, project.console_sessions.first), project_monitoring_path(project),
      project_proxy_path(project), project_config_path(project), project_settings_path(project),
      new_project_environment_variable_path(project), new_project_project_file_path(project), edit_settings_path,
      project_releases_path(project), project_containers_path(project, run_id: run.id), project_deploy_preview_path(project),
      project_monitoring_path(project, range: "30d"), servers_path, new_server_path,
      server_path(Server.find_by!(host: "192.0.2.10")), edit_server_path(Server.find_by!(host: "192.0.2.10")),
      status_board_path(Setting.instance.status_board_token) ]
  end

  %w[ en es ].each do |locale|
    it "has every text of every page in #{locale}" do
      sign_in
      patch preferences_path, params: { locale: locale }

      [ new_session_path, *pages ].each do |path|
        get path, headers: { "Turbo-Frame" => (path.include?("/releases") ? "releases" : path.include?("/deploy_preview") ? "deploy_preview" : path.include?("/containers") ? "containers" : path.include?("/proxy") ? "proxy_data" : nil) }.compact
        expect(response).to have_http_status(:ok), path
        expect(response.body).not_to include("translation_missing", "Translation missing"), "#{path}: #{response.body[/translation_missing[^>]*>[^<]*/]}"
      end
    end
  end

  it "speaks Spanish when the browser asks for it, and remembers a choice" do
    get new_session_path, headers: { "Accept-Language" => "es-ES,es;q=0.9,en;q=0.8" }
    expect(response.body).to include("Iniciar sesión", 'lang="es"')

    patch preferences_path, params: { locale: "en" }
    get new_session_path, headers: { "Accept-Language" => "es-ES" }
    expect(response.body).to include("Sign in")
  end

  it "remembers the theme" do
    get new_session_path
    expect(response.body).not_to include("data-theme=")

    patch preferences_path, params: { theme: "light" }
    get new_session_path
    expect(response.body).to include('data-theme="light"', 'content="light"')

    patch preferences_path, params: { theme: "neon" }
    get new_session_path
    expect(response.body).to include('data-theme="light"')
  end
end
