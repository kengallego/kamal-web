require "rails_helper"

RSpec.describe "Status board" do
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
end
