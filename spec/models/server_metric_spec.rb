require "rails_helper"

RSpec.describe ServerMetric do
  it "normalizes app memory and disk to the machine totals" do
    metric = described_class.new(memory_total: 8000, memory_used: 6000, app_memory_used: 1000,
      disk_total: 10000, disk_used: 9000, app_disk_used: 2000)
    expect(metric.app_memory_percent).to eq(12.5)
    expect(metric.app_disk_percent).to eq(20.0)
    expect(metric.memory_percent).to eq(75.0)
    expect(metric.disk_percent).to eq(90.0)
  end

  it "leaves old samples and missing host capacity unknown" do
    expect(described_class.new(memory_total: 8000).app_memory_percent).to be_nil
    expect(described_class.new(app_disk_used: 100, disk_total: 0).app_disk_percent).to be_nil
  end
end
