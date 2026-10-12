# Averages the last complete hours of server metrics, for the monitoring
# history past 24 hours. Rolling up two hours covers a missed run.
class RollUpMetricsJob < ApplicationJob
  queue_as :monitoring

  def perform
    hour = 1.hour.ago.beginning_of_hour
    [ hour - 1.hour, hour ].each { |start| HourlyMetric.roll_up(start) }
    HourlyMetric.where(hour: ...HourlyMetric::RETENTION.ago).delete_all
  end
end
