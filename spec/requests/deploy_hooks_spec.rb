require "rails_helper"

RSpec.describe "Deploy hooks" do
  let(:project) { create(:project, branch: "main") }

  it "queues a deploy" do
    expect {
      post deploy_hook_path(project.deploy_webhook_token)
    }.to have_enqueued_job(CommandRunJob)

    expect(response).to have_http_status(:created)
    expect(CommandRun.last).to have_attributes(kind: "deploy", trigger: "webhook")
  end

  it "ignores pushes to other branches" do
    post deploy_hook_path(project.deploy_webhook_token), params: { ref: "refs/heads/feature" }, as: :json

    expect(response).to have_http_status(:accepted)
    expect(CommandRun.count).to eq(0)
  end

  it "deploys pushes to the project branch" do
    post deploy_hook_path(project.deploy_webhook_token), params: { ref: "refs/heads/main" }, as: :json
    expect(response).to have_http_status(:created)
  end

  it "returns 404 for unknown tokens" do
    post deploy_hook_path("nope")
    expect(response).to have_http_status(:not_found)
  end

  it "rejects a deploy while another is running" do
    post deploy_hook_path(project.deploy_webhook_token)
    post deploy_hook_path(project.deploy_webhook_token)

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
