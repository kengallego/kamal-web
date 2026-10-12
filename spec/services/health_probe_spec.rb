require "rails_helper"

RSpec.describe HealthProbe do
  let(:project) do
    create(:project, config_snapshots: {
      "" => { "proxy_hosts" => [ "demo.example.com", "*.demo.example.com" ], "healthcheck_path" => "/health" },
      "staging" => { "proxy_hosts" => [ "staging.example.com" ], "proxy_ssl" => false }
    })
  end

  it "requests each domain at the health check path" do
    expect(described_class.new(project).urls).to eq([ "https://demo.example.com/health", "http://staging.example.com/up" ])
  end

  it "records the response" do
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      client = server.accept
      client.gets
      client.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
      client.close
    end

    check = described_class.new(project).check("http://127.0.0.1:#{server.addr[1]}/up")
    expect(check).to be_up
    expect(check.status_code).to eq(200)
  ensure
    thread&.join
    server&.close
  end

  it "records connection errors" do
    port = TCPServer.new("127.0.0.1", 0).then { |server| server.addr[1].tap { server.close } }

    check = described_class.new(project).check("http://127.0.0.1:#{port}/up")
    expect(check).not_to be_up
    expect(check.error).to include("ECONNREFUSED")
  end
end
