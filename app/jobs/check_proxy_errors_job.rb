# Reads kamal-proxy's recent access log for 5xx bursts.
class CheckProxyErrorsJob < ApplicationJob
  queue_as :monitoring

  def perform
    Project.where(monitoring_enabled: true).find_each do |project|
      AlertMonitor.new(project).check_proxy unless project.ssh_keys.empty?
    end
  end
end
