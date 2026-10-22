# Keeps each database's status current and applies the firewall rules again,
# since they are lost when a server reboots.
class CheckDatabasesJob < ApplicationJob
  queue_as :monitoring

  def perform
    Database.where.not(status: "provisioning").find_each(&:check!)
  end
end
