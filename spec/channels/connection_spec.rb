require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  it "only accepts signed-in browsers" do
    expect { connect "/cable" }.to have_rejected_connection

    cookies.signed[Authentication::COOKIE] = AccessPassword.fingerprint
    expect { connect "/cable" }.not_to raise_error
  end
end
