require "rails_helper"

RSpec.describe CheckForUpdatesJob do
  def stub_github(response)
    http = instance_double(Net::HTTP, get: response)
    allow(Net::HTTP).to receive(:start).with("api.github.com", 443, hash_including(use_ssl: true)).and_yield(http)
  end

  it "records the latest release and tells when it's newer" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return({ tag_name: "v9.0.0", html_url: "https://github.com/kengallego/kamal-web/releases/tag/v9.0.0" }.to_json)
    stub_github(response)

    described_class.perform_now

    setting = Setting.instance
    expect(setting.latest_version).to eq("9.0.0")
    expect(setting.update_available?).to be(true)
    expect(setting.update_checked_at).to be_present
  end

  it "treats a repository without releases as up to date" do
    stub_github(Net::HTTPNotFound.new("1.1", "404", "Not Found"))

    described_class.perform_now

    expect(Setting.instance.update_available?).to be(false)
  end

  it "can be turned off" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("KAMAL_WEB_UPDATE_CHECK").and_return("false")
    expect(Net::HTTP).not_to receive(:start)

    described_class.perform_now
  end

  it "keeps quiet when GitHub can't be reached" do
    allow(Net::HTTP).to receive(:start).and_raise(SocketError, "getaddrinfo failed")

    expect { described_class.perform_now }.not_to raise_error
  end
end
