require "rails_helper"

RSpec.describe "Authentication" do
  it "requires signing in" do
    create(:user)
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

  it "rejects wrong passwords and unknown accounts" do
    user = create(:user)
    post session_path, params: { email_address: user.email_address, password: "wrong password" }
    expect(flash[:alert]).to eq("Wrong password or code.")
    post session_path, params: { email_address: "nobody@example.com", password: AuthenticationHelpers::PASSWORD }

    get root_path
    expect(response).to redirect_to(new_session_path)
    expect(AuditEvent.where(action: "sessions#failed").pluck(:actor)).to eq([ user.email_address, "nobody@example.com" ])
  end

  it "no longer signs in with the instance password once an account exists" do
    create(:user)
    post session_path, params: { password: AccessPassword::DEVELOPMENT_PASSWORD }
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "signs a browser out when its account is deleted or its password changes elsewhere" do
    user = sign_in
    user.update!(password: "another long password")

    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "refuses to sign in with a short instance password" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("KAMAL_WEB_PASSWORD").and_return("short")

    get new_session_path
    expect(response.body).to include("at least 12 characters")
  end

  describe "the first account" do
    let(:account) { { name: "Ana", email_address: "Ana@Example.com", password: "a long password", password_confirmation: "a long password" } }

    it "is created with the instance password, which then stops working" do
      get new_session_path
      expect(response).to redirect_to(new_setup_path)

      post setup_path, params: { instance_password: "wrong", user: account }
      expect(response).to have_http_status(:unprocessable_content)
      expect(User.count).to eq(0)

      post setup_path, params: { instance_password: AccessPassword::DEVELOPMENT_PASSWORD, user: account }
      expect(response).to redirect_to(root_url)
      expect(User.sole).to have_attributes(name: "Ana", email_address: "ana@example.com")
      expect(AuditEvent.sole).to have_attributes(action: "setups#create", actor: "Ana <ana@example.com>")

      delete session_path
      get new_setup_path
      expect(response).to redirect_to(new_session_path)
      post setup_path, params: { instance_password: AccessPassword::DEVELOPMENT_PASSWORD, user: account.merge(email_address: "eve@example.com") }
      expect(User.count).to eq(1)
    end
  end

  context "with an authenticator app" do
    let(:secret) { Totp.generate_secret }

    before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

    it "asks for the account's own code" do
      user = create(:user, otp_secret: secret)

      sign_in(user)
      expect(flash[:alert]).to eq("Wrong password or code.")

      sign_in(user, code: Totp.code(secret))
      expect(response).to redirect_to(root_url)
    end

    it "asks accounts without one for the instance's code" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KAMAL_WEB_TOTP_SECRET").and_return(secret)

      sign_in
      expect(response).to redirect_to(new_session_path)

      sign_in(code: Totp.code(secret))
      expect(response).to redirect_to(root_url)
    end

    it "is set up from the account page with a code from the app" do
      user = sign_in
      get new_two_factor_path
      pending_secret = session[:pending_otp_secret]

      post two_factor_path, params: { code: "000000" }
      expect(user.reload.two_factor?).to be(false)

      post two_factor_path, params: { code: Totp.code(pending_secret) }
      expect(user.reload.otp_secret).to eq(pending_secret)
    end
  end

  describe "accounts" do
    it "are added and deleted by anyone signed in, except themselves" do
      me = sign_in
      post users_path, params: { user: { name: "Bo", email_address: "bo@example.com", password: "a long password", password_confirmation: "a long password" } }
      expect(response).to redirect_to(users_path)
      bo = User.find_by!(email_address: "bo@example.com")

      delete user_path(me)
      expect(flash[:alert]).to eq("You can't delete your own account.")

      delete user_path(bo)
      expect(User.all).to eq([ me ])
    end

    it "change their own password only with the current one" do
      user = sign_in
      patch account_path, params: { current_password: "wrong", user: { name: "New", email_address: user.email_address, password: "" } }
      expect(response).to have_http_status(:unprocessable_content)

      patch account_path, params: { current_password: AuthenticationHelpers::PASSWORD, user: { name: "New", email_address: user.email_address, password: "a new long password", password_confirmation: "a new long password" } }
      expect(user.reload).to have_attributes(name: "New")
      expect(user.authenticate("a new long password")).to be_truthy

      get root_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "activity" do
    it "records who changed what, without the parameters" do
      user = sign_in
      project = create(:project)
      post project_environment_variables_path(project), params: { environment_variable: { key: "TOKEN", value: "s3cret" } }

      event = AuditEvent.find_by!(action: "projects/environment_variables#create")
      expect(event).to have_attributes(user: user, actor: user.label, project: project, ip_address: "127.0.0.1")
      expect(event.details).to include("key" => "TOKEN")
      expect(event.details.to_json).not_to include("s3cret")

      get audit_events_path
      expect(CGI.unescapeHTML(response.body)).to include("Added a secret", user.label)
    end

    it "attributes commands to who ran them" do
      user = sign_in
      project = create(:project)
      post project_command_runs_path(project), params: { kind: "app_logs", options: { lines: "5" } }

      expect(CommandRun.last.user).to eq(user)
      expect(CommandRun.last.triggered_by).to eq(user.name)
    end
  end

  context "with allowed IPs" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KAMAL_WEB_ALLOWED_IPS").and_return("203.0.113.7, 10.0.0.0/8")
      create(:user)
    end

    it "only serves the dashboard to those addresses" do
      get new_session_path, env: { "REMOTE_ADDR" => "198.51.100.1" }
      expect(response).to have_http_status(:forbidden)

      get new_session_path, env: { "REMOTE_ADDR" => "10.1.2.3" }
      expect(response).to have_http_status(:ok)
    end

    it "still accepts the deploy webhook from anywhere" do
      project = create(:project)

      post deploy_hook_path(project.deploy_webhook_token), headers: { "Authorization" => "Bearer #{project.deploy_webhook_secret}" }, env: { "REMOTE_ADDR" => "198.51.100.1" }
      expect(response).to have_http_status(:created)
    end

    it "refuses to start with an invalid entry" do
      allow(ENV).to receive(:[]).with("KAMAL_WEB_ALLOWED_IPS").and_return("203.0.113.7, not-an-ip")
      expect(AccessPassword.problem).to include("not-an-ip")
    end
  end
end
