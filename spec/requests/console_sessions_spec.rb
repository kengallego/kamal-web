require "rails_helper"

RSpec.describe "Console sessions" do
  let(:project) { create(:project) }

  it "opens a console" do
    sign_in

    get project_console_sessions_path(project)
    expect(response).to have_http_status(:ok)

    post project_console_sessions_path(project), params: { kind: "rails" }
    session = ConsoleSession.last
    expect(response).to redirect_to(project_console_session_path(project, session))

    follow_redirect!
    expect(response.body).to include("data-console-session-id-value=\"#{session.id}\"")
  end
end
