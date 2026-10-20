require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  it "gives signed-in browsers full access" do
    expect { connect "/cable" }.to have_rejected_connection

    session = create(:user).sessions.create!
    cookies.signed[Authentication::COOKIE] = session.id
    connect "/cable"
    expect(connection.access).to eq(:full)
    expect(connection.session).to eq(session)

    session.destroy
    expect { connect "/cable" }.to have_rejected_connection
  end

  it "lets a status board in with its cookie while the board is enabled" do
    setting = Setting.instance
    setting.update!(status_board_enabled: true)

    cookies.signed[StatusBoardsController::COOKIE] = "wrong"
    expect { connect "/cable" }.to have_rejected_connection

    cookies.signed[StatusBoardsController::COOKIE] = setting.status_board_token
    connect "/cable"
    expect(connection.access).to eq(:status_board)

    setting.update!(status_board_enabled: false)
    expect { connect "/cable" }.to have_rejected_connection
  end
end
