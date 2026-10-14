# Server metrics averaged per hour, kept longer than the minute samples so
# slow trends such as a disk filling up stay visible. Disk keeps the hour's
# peak.
class HourlyMetric < ApplicationRecord
  RETENTION = 30.days

  belongs_to :project

  def self.roll_up(hour)
    hour = hour.beginning_of_hour
    samples = ServerMetric.successful.where(collected_at: hour...(hour + 1.hour)).group_by { |metric| [ metric.project_id, metric.host ] }

    rows = samples.map do |(project_id, host), metrics|
      {
        project_id: project_id, host: host, hour: hour, samples: metrics.size,
        cpu_percent: average(metrics.map(&:cpu_percent)),
        load_percent: average(metrics.map(&:load_percent)),
        memory_percent: average(metrics.map(&:memory_percent)),
        disk_percent: metrics.filter_map(&:disk_percent).max,
        app_cpu_percent: average(metrics.map(&:app_cpu_percent)),
        app_memory_percent: average(metrics.map(&:app_memory_percent)),
        app_disk_percent: metrics.filter_map(&:app_disk_percent).max
      }
    end
    upsert_all(rows, unique_by: %i[ project_id host hour ]) if rows.any?
  end

  def self.average(values)
    values = values.compact
    (values.sum / values.size).round(1) if values.any?
  end
end
