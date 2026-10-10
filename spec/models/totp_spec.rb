require "rails_helper"

RSpec.describe Totp do
  # RFC 6238 test vector: the ASCII secret "12345678901234567890".
  let(:secret) { "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" }

  # Used codes are remembered in the cache, which is a null store in tests.
  before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

  it "matches the RFC 6238 test vectors" do
    expect(described_class.code(secret, Time.at(59))).to eq("287082")
    expect(described_class.code(secret, Time.at(1_111_111_109))).to eq("081804")
    expect(described_class.code(secret, Time.at(2_000_000_000))).to eq("279037")
  end

  it "accepts a code once, allowing for one step of clock drift" do
    now = Time.at(1_111_111_109)
    previous = described_class.code(secret, now - 30)

    expect(described_class.verify(secret, previous, time: now)).to be(true)
    expect(described_class.verify(secret, previous, time: now)).to be(false)
    expect(described_class.verify(secret, described_class.code(secret, now - 90), time: now)).to be(false)
    expect(described_class.verify(secret, "abc123", time: now)).to be(false)
  end

  it "generates secrets authenticator apps accept" do
    expect(described_class.valid_secret?(described_class.generate_secret)).to be(true)
    expect(described_class.valid_secret?("too-short")).to be(false)
  end
end
