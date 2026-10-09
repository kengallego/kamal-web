require "rails_helper"

RSpec.describe AdminBootstrap do
  let(:io) { StringIO.new }

  it "creates the admin with a generated password and prints it once" do
    user = described_class.new(email: "ops@example.com", password: "", io: io).call

    expect(user).to be_admin
    password = io.string[/Password: (\S+)/, 1]
    expect(User.authenticate_by(email_address: "ops@example.com", password: password)).to eq(user)

    expect(described_class.new(io: io2 = StringIO.new).call).to be_nil
    expect(io2.string).to be_empty
  end

  it "uses the configured password without printing it" do
    described_class.new(email: "ops@example.com", password: "a configured password", io: io).call

    expect(io.string).not_to include("a configured password")
    expect(User.authenticate_by(email_address: "ops@example.com", password: "a configured password")).to be_present
  end

  it "falls back to a default email" do
    expect(described_class.new(email: nil, password: nil, io: io).call.email_address).to eq("admin@example.com")
  end
end
