# Keeps the database from growing forever: old command runs (their output is
# most of it), console sessions and resolved alerts.
class PruneHistoryJob < ApplicationJob
  queue_as :default

  def perform
    CommandRun.prune!
    ConsoleSession.where(created_at: ...CommandRun::RETENTION.ago).delete_all
    Alert.prune!
  end
end
