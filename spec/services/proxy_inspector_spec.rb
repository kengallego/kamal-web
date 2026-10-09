require "rails_helper"

RSpec.describe ProxyInspector do
  subject(:inspector) { described_class.allocate }

  it "parses kamal-proxy list output" do
    output = <<~TEXT
      Service      Host               Path  Target            State    TLS
      demo-web     demo.example.com   /     abc123:80         running  yes
    TEXT

    route = inspector.parse_routes(output).first

    expect(route.service).to eq("demo-web")
    expect(route.host).to eq("demo.example.com")
    expect(route.state).to eq("running")
    expect(route.tls).to eq("yes")
  end

  it "parses request lines from the access log, newest first" do
    output = <<~TEXT
      {"time":"2026-10-14T10:00:00Z","level":"INFO","msg":"Request","host":"demo.example.com","path":"/","status":200,"duration":2500000,"method":"GET","service":"demo-web"}
      not json
      {"time":"2026-10-14T10:00:01Z","level":"INFO","msg":"Request","host":"demo.example.com","path":"/boom","status":500,"duration":1000000,"method":"POST","service":"demo-web"}
      {"time":"2026-10-14T10:00:02Z","level":"INFO","msg":"Deployed","service":"demo-web"}
    TEXT

    requests = inspector.parse_requests(output)

    expect(requests.map(&:path)).to eq([ "/boom", "/" ])
    expect(requests.first.status_class).to eq("5xx")
    expect(requests.last.duration_ms).to eq(2.5)
  end
end
