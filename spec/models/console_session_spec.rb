require "rails_helper"

RSpec.describe ConsoleSession do
  let(:project) { create(:project, config_snapshots: { "" => { "roles" => { "web" => [ "192.0.2.10", "192.0.2.11" ] }, "accessories" => {} }, "staging" => { "roles" => { "web" => [ "192.0.2.20" ] }, "accessories" => {} } }) }

  it "builds an interactive exec in the running container" do
    session = project.console_sessions.create!(kind: "rails", destination: "staging", host: "192.0.2.20")

    expect(session.arguments).to eq([ "app", "exec", "--interactive", "--reuse", "--hosts", "192.0.2.20", "bin/rails console", "-d", "staging" ])
  end

  it "only accepts known kinds, destinations and hosts" do
    expect(project.console_sessions.new(kind: "rm -rf").valid?).to be(false)
    expect(project.console_sessions.new(kind: "rails", destination: "production").valid?).to be(false)
    expect(project.console_sessions.new(kind: "rails", host: "192.0.2.20").valid?).to be(false)
    expect(project.console_sessions.new(kind: "shell", host: "192.0.2.11").valid?).to be(true)
  end

  it "can be claimed once, shortly after creation" do
    session = project.console_sessions.create!(kind: "rails")

    expect(session.claim!).to be(true)
    expect(session.claim!).to be(false)

    late = project.console_sessions.create!(kind: "rails", created_at: 10.minutes.ago)
    expect(late.claim!).to be(false)
  end
end
