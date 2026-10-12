# Requests every app's health check path through its domains each minute.
class CheckAppHealthJob < ApplicationJob
  queue_as :monitoring

  def perform
    HealthCheck.where(checked_at: ...HealthCheck::RETENTION.ago).delete_all

    Project.where(monitoring_enabled: true).find_each do |project|
      AlertMonitor.new(project).check_health(HealthProbe.new(project).call)
    end
  end
end
