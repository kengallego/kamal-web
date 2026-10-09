require "rails_helper"

RSpec.describe ServerProbe do
  it "parses the probe output" do
    separator = "#{ServerProbe::SEPARATOR}\n"
    output = [
      "cpu  100 0 100 800 0 0 0 0 0 0\n",
      "0.50 0.40 0.30 1/200 1234\n",
      "2\n",
      "4000000000 1000000000\n",
      "50000000000 25000000000\n",
      %({"Names":"demo-web-abc","Image":"acme/demo:abc","Status":"Up 2 hours","State":"running"}\n),
      "cpu  150 0 150 900 0 0 0 0 0 0\n"
    ].join(separator)

    attributes = described_class.new(build(:project), "192.0.2.10").parse(output)

    expect(attributes).to include(load_1: 0.5, cpu_count: 2, memory_total: 4_000_000_000, memory_used: 1_000_000_000, disk_used: 25_000_000_000)
    expect(attributes[:cpu_percent]).to eq(50.0)
    expect(attributes[:containers].first["Names"]).to eq("demo-web-abc")
  end
end
