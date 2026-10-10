require "rails_helper"

RSpec.describe "Authentication" do
  it "requires signing in" do
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "signs in and out" do
    sign_in
    expect(response).to redirect_to(root_url)

    get root_path
    expect(response).to have_http_status(:ok)

    delete session_path
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "rejects wrong passwords" do
    post session_path, params: { password: "wrong password" }
    expect(response).to redirect_to(new_session_path)

    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "signs everybody out when the password changes" do
    sign_in
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("KAMAL_WEB_PASSWORD").and_return("a different password")

    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "refuses to sign in with a short password" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("KAMAL_WEB_PASSWORD").and_return("short")

    get new_session_path
    expect(response.body).to include("at least 12 characters")

    post session_path, params: { password: "short" }
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "has no user, profile or password reset pages" do
    sign_in
    %w[ /users /profile/edit /passwords/new ].each do |path|
      get path
      expect(response).to have_http_status(:not_found), path
    end
  end
end
