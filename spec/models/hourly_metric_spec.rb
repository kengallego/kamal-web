require "rails_helper"

RSpec.describe HourlyMetric do
  it "averages an hour of samples per host, keeping the disk's peak" do
    project = create(:project)
    hour = 2.hours.ago.beginning_of_hour
    [ [ 10, 40, 50 ], [ 30, 60, 70 ] ].each_with_index do |(cpu, memory, disk), index|
      project.server_metrics.create!(host: "192.0.2.10", collected_at: hour + index.minutes, cpu_percent: cpu,
        memory_total: 100, memory_used: memory, disk_total: 100, disk_used: disk,
        app_cpu_percent: cpu / 2.0, app_memory_used: memory / 2, app_disk_used: disk / 2)
    end
    project.server_metrics.create!(host: "192.0.2.10", collected_at: hour + 5.minutes, error: "timeout")

    2.times { HourlyMetric.roll_up(hour) }

    expect(HourlyMetric.sole).to have_attributes(host: "192.0.2.10", hour: hour, samples: 2, cpu_percent: 20.0, memory_percent: 50.0, disk_percent: 70.0)
    expect(HourlyMetric.sole).to have_attributes(app_cpu_percent: 10.0, app_memory_percent: 25.0, app_disk_percent: 35.0)
  end
end
