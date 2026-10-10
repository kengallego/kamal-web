require "rails_helper"

RSpec.describe Turbo::StreamsChannel, type: :channel do
  it "lets status boards listen to the status board stream only" do
    stub_connection access: :status_board

    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name(StatusBoardsController::STREAM)
    expect(subscription).to be_confirmed

    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name(create(:project))
    expect(subscription).to be_rejected
  end
end

RSpec.describe ConsoleChannel, type: :channel do
  it "keeps status boards out of web consoles" do
    session = create(:project).console_sessions.create!(kind: "rails")
    stub_connection access: :status_board

    subscribe id: session.id
    expect(subscription).to be_rejected
  end
end
