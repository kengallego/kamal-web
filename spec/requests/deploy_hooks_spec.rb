require "rails_helper"

RSpec.describe "Deploy hooks" do
  let(:project) { create(:project, branch: "main") }
  let(:bearer) { { "Authorization" => "Bearer #{project.deploy_webhook_secret}" } }

  it "queues a deploy" do
    expect {
      post deploy_hook_path(project.deploy_webhook_token), headers: bearer
    }.to have_enqueued_job(CommandRunJob)

    expect(response).to have_http_status(:created)
    expect(CommandRun.last).to have_attributes(kind: "deploy", trigger: "webhook", user: nil)
    expect(AuditEvent.last).to have_attributes(action: "deploy_hooks#create", project: project, ip_address: "127.0.0.1")
  end

  it "needs the secret, not just the URL" do
    post deploy_hook_path(project.deploy_webhook_token)
    expect(response).to have_http_status(:unauthorized)

    post deploy_hook_path(project.deploy_webhook_token), headers: { "Authorization" => "Bearer wrong" }
    expect(response).to have_http_status(:unauthorized)
    expect(CommandRun.count).to eq(0)
  end

  it "checks GitHub's signature of the payload" do
    body = { ref: "refs/heads/main" }.to_json
    signature = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", project.deploy_webhook_secret, body)
    headers = { "Content-Type" => "application/json", "X-Hub-Signature-256" => signature }

    post deploy_hook_path(project.deploy_webhook_token), params: body.sub("main", "evil"), headers: headers
    expect(response).to have_http_status(:unauthorized)

    post deploy_hook_path(project.deploy_webhook_token), params: body, headers: headers
    expect(response).to have_http_status(:created)
  end

  it "ignores a GitHub delivery it already received" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    body = { ref: "refs/heads/main" }.to_json
    headers = { "Content-Type" => "application/json", "X-GitHub-Delivery" => "abc-123",
      "X-Hub-Signature-256" => "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", project.deploy_webhook_secret, body) }

    post deploy_hook_path(project.deploy_webhook_token), params: body, headers: headers
    project.command_runs.last.update!(status: "succeeded")
    post deploy_hook_path(project.deploy_webhook_token), params: body, headers: headers

    expect(response).to have_http_status(:accepted)
    expect(CommandRun.count).to eq(1)
  end

  it "accepts GitLab's secret token" do
    post deploy_hook_path(project.deploy_webhook_token), headers: { "X-Gitlab-Token" => project.deploy_webhook_secret }
    expect(response).to have_http_status(:created)
  end

  it "accepts the URL alone for projects from before secrets, until one is generated" do
    project.update_columns(deploy_webhook_secret: nil)
    post deploy_hook_path(project.deploy_webhook_token)
    expect(response).to have_http_status(:created)
  end

  it "ignores pushes to other branches" do
    post deploy_hook_path(project.deploy_webhook_token), params: { ref: "refs/heads/feature" }, headers: bearer, as: :json

    expect(response).to have_http_status(:accepted)
    expect(CommandRun.count).to eq(0)
  end

  it "deploys pushes to the project branch" do
    post deploy_hook_path(project.deploy_webhook_token), params: { ref: "refs/heads/main" }, headers: bearer, as: :json
    expect(response).to have_http_status(:created)
  end

  it "returns 404 for unknown tokens" do
    post deploy_hook_path("nope")
    expect(response).to have_http_status(:not_found)
  end

  it "rejects a deploy while another is running" do
    post deploy_hook_path(project.deploy_webhook_token), headers: bearer
    post deploy_hook_path(project.deploy_webhook_token), headers: bearer

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "rotates the URL and the secret together" do
    sign_in
    token, secret = project.deploy_webhook_token, project.deploy_webhook_secret
    post project_webhook_token_path(project)

    expect(project.reload.deploy_webhook_token).not_to eq(token)
    expect(project.deploy_webhook_secret).to be_present
    expect(project.deploy_webhook_secret).not_to eq(secret)
  end
end
