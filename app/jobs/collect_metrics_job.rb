class CollectMetricsJob < ApplicationJob
  queue_as :monitoring

  def perform
    ServerMetric.where(collected_at: ...ServerMetric::RETENTION.ago).delete_all

    Project.where(monitoring_enabled: true).find_each do |project|
      next if project.ssh_keys.empty?

      project.hosts.each { |host| ServerProbe.new(project, host).collect }
      AlertMonitor.new(project).check_hosts
    end
  end
end
