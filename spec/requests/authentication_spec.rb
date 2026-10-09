require "rails_helper"

RSpec.describe "Authentication" do
  it "requires signing in" do
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "signs in and out" do
    user = create(:user)
    sign_in(user)
    expect(response).to redirect_to(root_url)

    get root_path
    expect(response).to have_http_status(:ok)

    delete session_path
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "rejects wrong passwords" do
    post session_path, params: { email_address: create(:user).email_address, password: "wrong password" }
    expect(response).to redirect_to(new_session_path)
  end

  it "hides email password reset when SMTP isn't configured" do
    allow(Rails.configuration.x).to receive(:password_reset_enabled).and_return(false)
    get new_password_path
    expect(response).to redirect_to(new_session_path)
  end
end
