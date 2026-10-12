require "rails_helper"

RSpec.describe AlertMonitor do
  let(:project) do
    create(:project, config_snapshots: { "" => {
      "service" => "demo", "primary_role" => "web", "roles" => { "web" => [ "192.0.2.10" ] }, "accessories" => {}, "proxy_hosts" => [ "demo.example.com" ]
    } })
  end
  let(:app) { { "Names" => "demo-web-abc123", "State" => "running" } }

  def sample(at, **attributes)
    project.server_metrics.create!(host: "192.0.2.10", collected_at: at.minutes.ago, memory_total: 100, memory_used: 10, disk_total: 100, disk_used: 10, containers: [ app ], **attributes)
  end

  def kinds
    project.alerts.active.pluck(:kind)
  end

  it "alerts on an unreachable host only after a few failed samples" do
    sample(3, error: "timeout")
    sample(2, error: "timeout")
    described_class.new(project).check_hosts
    expect(kinds).to be_empty

    sample(1, error: "timeout")
    described_class.new(project).check_hosts
    expect(kinds).to eq([ "host_unreachable" ])

    sample(0)
    described_class.new(project).check_hosts
    expect(kinds).to be_empty
  end

  it "alerts on a full disk right away and on memory once it stays high" do
    Setting.instance.update!(alert_disk_percent: 90, alert_memory_percent: 90)
    sample(2, memory_used: 95)
    sample(1, memory_used: 95)
    sample(0, memory_used: 95, disk_used: 92)
    described_class.new(project).check_hosts

    expect(kinds).to contain_exactly("disk", "memory")
    expect(project.alerts.find_by(kind: "disk").message).to eq("92%")
  end

  it "alerts when the app's container is gone, unless it was stopped from Kamal Web" do
    sample(1, containers: [])
    sample(0, containers: [])
    described_class.new(project).check_hosts
    expect(kinds).to eq([ "app_down" ])

    project.alerts.delete_all
    project.command_runs.create!(kind: "app_stop").update_columns(status: "succeeded")
    described_class.new(project).check_hosts
    expect(kinds).to be_empty
  end

  it "alerts when a domain fails its health check twice and when its certificate is expiring" do
    url = "https://demo.example.com/up"
    first = project.health_checks.create!(url: url, checked_at: 1.minute.ago, error: "Net::OpenTimeout: execution expired")
    described_class.new(project).check_health([ first ])
    expect(kinds).to be_empty

    second = project.health_checks.create!(url: url, checked_at: Time.current, status_code: 502)
    described_class.new(project).check_health([ second ])
    expect(project.alerts.active.sole).to have_attributes(kind: "health_check", subject: url, message: "HTTP 502")

    ok = project.health_checks.create!(url: url, checked_at: Time.current, status_code: 200, certificate_expires_at: 5.days.from_now)
    described_class.new(project).check_health([ ok ])
    expect(project.alerts.active.sole).to have_attributes(kind: "certificate", subject: "demo.example.com")
  end

  it "alerts on a burst of 5xx responses" do
    requests = Array.new(30) do |index|
      ProxyInspector::Request.new(time: 1.minute.ago, host: "demo.example.com", path: "/", method: "GET", status: index < 5 ? 500 : 200, duration_ms: 3, service: "demo-web", remote_addr: nil)
    end
    allow(ProxyInspector).to receive(:new).and_return(instance_double(ProxyInspector, requests: requests))

    described_class.new(project).check_proxy
    expect(project.alerts.active.sole).to have_attributes(kind: "proxy_errors", message: "5/30")
  end
end
