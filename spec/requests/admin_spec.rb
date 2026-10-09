require "rails_helper"

RSpec.describe "Administration" do
  it "lets admins manage users" do
    sign_in create(:user, :admin)

    post users_path, params: { user: { email_address: "new@example.com", role: "viewer", password: "long enough password" } }
    expect(User.find_by(email_address: "new@example.com")).to be_present

    get users_path
    expect(response).to have_http_status(:ok)
  end

  it "keeps non-admins out of user management" do
    sign_in create(:user)

    get users_path
    expect(response).to redirect_to(root_path)
  end

  it "requires the current password to change your own" do
    user = create(:user)
    sign_in user

    patch profile_path, params: { user: { password: "a brand new password", password_confirmation: "a brand new password", password_challenge: "wrong" } }
    expect(response).to have_http_status(:unprocessable_entity)

    patch profile_path, params: { user: { password: "a brand new password", password_confirmation: "a brand new password", password_challenge: user.password } }
    expect(User.authenticate_by(email_address: user.email_address, password: "a brand new password")).to eq(user)
  end

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
