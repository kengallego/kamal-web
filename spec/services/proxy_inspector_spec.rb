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

  it "ignores the colors kamal-proxy adds" do
    output = "\e[3;94mService\e[0m   \e[3;94mHost\e[0m       \e[3;94mPath\e[0m  \e[3;94mTarget\e[0m   \e[3;94mState\e[0m    \e[3;94mTLS\e[0m\n" \
      "\e[1;34mshop-web\e[0m  \e[mshop.test\e[0m  \e[m/\e[0m     \e[mabc:80\e[0m   \e[mrunning\e[0m  \e[mno\e[0m\n"

    route = inspector.parse_routes(output).first

    expect([ route.service, route.host, route.target, route.tls ]).to eq([ "shop-web", "shop.test", "abc:80", "no" ])
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
