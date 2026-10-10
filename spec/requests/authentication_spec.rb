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

  context "with an authenticator app" do
    let(:secret) { Totp.generate_secret }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KAMAL_WEB_TOTP_SECRET").and_return(secret)
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    end

    it "asks for the code and needs it to sign in" do
      get new_session_path
      expect(response.body).to include("Code from your authenticator app")

      post session_path, params: { password: AccessPassword::DEVELOPMENT_PASSWORD }
      expect(flash[:alert]).to eq("Wrong password or code.")

      post session_path, params: { password: AccessPassword::DEVELOPMENT_PASSWORD, code: Totp.code(secret) }
      expect(response).to redirect_to(root_url)
      get root_path
      expect(response).to have_http_status(:ok)
    end
  end

  context "with allowed IPs" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KAMAL_WEB_ALLOWED_IPS").and_return("203.0.113.7, 10.0.0.0/8")
    end

    it "only serves the dashboard to those addresses" do
      get new_session_path, env: { "REMOTE_ADDR" => "198.51.100.1" }
      expect(response).to have_http_status(:forbidden)

      get new_session_path, env: { "REMOTE_ADDR" => "10.1.2.3" }
      expect(response).to have_http_status(:ok)
    end

    it "still accepts the deploy webhook from anywhere" do
      project = create(:project)

      post deploy_hook_path(project.deploy_webhook_token), env: { "REMOTE_ADDR" => "198.51.100.1" }
      expect(response).to have_http_status(:created)
    end

    it "refuses to start with an invalid entry" do
      allow(ENV).to receive(:[]).with("KAMAL_WEB_ALLOWED_IPS").and_return("203.0.113.7, not-an-ip")
      expect(AccessPassword.problem).to include("not-an-ip")
    end
  end
end
