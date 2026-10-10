require "rails_helper"

RSpec.describe TrafficChart do
  def request(time, status)
    ProxyInspector::Request.new(time: time, host: "shop.test", path: "/", method: "GET", status: status, duration_ms: 1.0, service: "shop-web", remote_addr: nil)
  end

  it "counts requests per minute and status class over the last hour" do
    now = Time.zone.parse("2026-10-15 10:30:40")
    chart = described_class.new([
      request(now - 10.seconds, 200), request(now - 20.seconds, 500), request(now - 5.minutes, 404),
      request(now - 2.hours, 200), request(nil, 200)
    ], now: now)

    expect(chart.buckets.size).to eq(60)
    expect(chart.buckets.last.counts).to include("2xx" => 1, "5xx" => 1)
    expect(chart.buckets[-6].counts["4xx"]).to eq(1)
    expect(chart.buckets.sum(&:total)).to eq(3)
    expect(chart.peak).to eq(2)
  end
end
