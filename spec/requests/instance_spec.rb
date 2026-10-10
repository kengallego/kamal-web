require "rails_helper"

RSpec.describe "Instance pages" do
  it "serves the status board only when enabled and with the right token" do
    setting = Setting.instance

    get status_board_path(setting.status_board_token)
    expect(response).to have_http_status(:not_found)

    setting.update!(status_board_enabled: true)
    create(:project)
    get status_board_path(setting.status_board_token)
    expect(response).to have_http_status(:ok)

    get status_board_path("wrong")
    expect(response).to have_http_status(:not_found)
  end

  it "shows when a newer Kamal Web is available" do
    sign_in
    get root_path
    expect(response.body).to include("Kamal Web #{KamalWeb::VERSION}")

    Setting.instance.update!(latest_version: "99.0.0", latest_version_url: "https://github.com/kengallego/kamal-web/releases/tag/v99.0.0")
    get root_path
    expect(response.body).to include("Kamal Web 99.0.0 is available")

    get edit_settings_path
    expect(response.body).to include("git pull &amp;&amp; kamal deploy")
  end

  it "refreshes open status boards when deploys or metrics change" do
    Setting.instance.update!(status_board_enabled: true)
    project = create(:project)

    expect { project.command_runs.create!(kind: "version") }.to have_enqueued_job(Turbo::Streams::BroadcastStreamJob)
    expect { project.server_metrics.create!(host: "192.0.2.10", collected_at: Time.current) }.to have_enqueued_job(Turbo::Streams::BroadcastStreamJob)

    get status_board_path(Setting.instance.status_board_token)
    expect(response.body).to include("turbo-cable-stream-source", 'name="turbo-refresh-method" content="morph"')
    expect(cookies[StatusBoardsController::COOKIE.to_s]).to be_present
  end
end
