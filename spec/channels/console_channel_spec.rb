require "rails_helper"

RSpec.describe ConsoleChannel, type: :channel do
  let(:project) { create(:project) }
  let(:session) { project.console_sessions.create!(kind: "rails") }

  before { allow_any_instance_of(ConsoleProcess).to receive(:start) }

  it "attaches a session only once" do
    stub_connection access: :full
    subscribe id: session.id, rows: 24, cols: 80
    expect(subscription).to be_confirmed
    expect(session.reload.started_at).to be_present

    subscribe id: session.id
    expect(subscription).to be_rejected
  end

  it "closes the session when the browser leaves" do
    allow_any_instance_of(ConsoleProcess).to receive(:stop)
    stub_connection access: :full
    subscribe id: session.id

    unsubscribe

    expect(session.reload.ended_at).to be_present
  end
end
