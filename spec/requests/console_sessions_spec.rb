require "rails_helper"

RSpec.describe "Console sessions" do
  let(:project) { create(:project) }

  it "lets deployers open a console" do
    sign_in create(:user)

    get project_console_sessions_path(project)
    expect(response).to have_http_status(:ok)

    post project_console_sessions_path(project), params: { kind: "rails" }
    session = ConsoleSession.last
    expect(response).to redirect_to(project_console_session_path(project, session))

    follow_redirect!
    expect(response.body).to include("data-console-session-id-value=\"#{session.id}\"")
  end

  it "keeps viewers out" do
    sign_in create(:user, :viewer)

    post project_console_sessions_path(project), params: { kind: "rails" }

    expect(ConsoleSession.count).to eq(0)
  end
end
