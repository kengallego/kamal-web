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

  def command(kind, status: "succeeded", destination: nil)
    project.command_runs.create!(kind: kind, destination: destination, status: status)
  end

  def failed_health_check(url = "https://demo.example.com/up")
    project.health_checks.create!(url: url, checked_at: Time.current, status_code: 503)
  end

  def proxy_errors
    Array.new(30) do
      ProxyInspector::Request.new(time: 1.minute.ago, host: "demo.example.com", path: "/", method: "GET", status: 503, duration_ms: 3, service: "demo-web", remote_addr: nil)
    end
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

  { "app_stop" => "app_start", "app_maintenance" => "app_live" }.each do |pause, resume|
    context "when #{pause} is intentional" do
      before do
        sample(1, containers: [])
        sample(0, containers: [])
        failed_health_check
        allow(ProxyInspector).to receive(:new).and_return(instance_double(ProxyInspector, requests: proxy_errors))
      end

      def check_availability
        monitor = described_class.new(project)
        monitor.check_hosts
        monitor.check_health([ failed_health_check ])
        monitor.check_proxy
      end

      it "resolves availability alerts and resumes alerting after #{resume}" do
        check_availability
        expect(kinds).to contain_exactly("app_down", "health_check", "proxy_errors")

        command(pause)
        check_availability
        expect(kinds).to be_empty
        expect(project.alerts.resolved.count).to eq(3)

        command(resume)
        check_availability
        expect(kinds).to contain_exactly("app_down", "health_check", "proxy_errors")
      end

      it "suppresses alerts while the command is running, but not if it fails" do
        run = command(pause, status: "running")
        check_availability
        expect(kinds).to be_empty

        run.update!(status: "failed")
        check_availability
        expect(kinds).to contain_exactly("app_down", "health_check", "proxy_errors")
      end

      it "keeps host and certificate alerts enabled" do
        command(pause)
        sample(0, disk_used: 99)
        check = failed_health_check
        check.update!(certificate_expires_at: 5.days.from_now)
        monitor = described_class.new(project)
        monitor.check_hosts
        monitor.check_health([ check ])

        expect(kinds).to contain_exactly("disk", "certificate")
      end

      it "does not suppress alerts for another destination" do
        project.update!(config_snapshots: project.config_snapshots.merge("staging" => {
          "service" => "demo", "roles" => { "web" => [ "192.0.2.10" ] }, "proxy_hosts" => [ "staging.example.com" ]
        }))
        command(pause)
        failed_health_check("https://staging.example.com/up")
        monitor = described_class.new(project)
        monitor.check_hosts
        monitor.check_health([ failed_health_check, failed_health_check("https://staging.example.com/up") ])

        expect(project.alerts.active.pluck(:kind, :subject)).to contain_exactly(
          [ "app_down", "192.0.2.10 (staging)" ], [ "health_check", "https://staging.example.com/up" ]
        )
      end
    end
  end

  it "keeps maintenance active when starting containers and keeps a stop active when going live" do
    command("app_maintenance")
    command("app_start")
    failed_health_check
    monitor = described_class.new(project)
    monitor.check_health([ failed_health_check ])
    expect(kinds).to be_empty

    command("app_stop")
    command("app_live")
    monitor.check_health([ failed_health_check ])
    expect(kinds).to be_empty
  end
end
