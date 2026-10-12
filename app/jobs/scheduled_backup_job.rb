# Writes a daily backup into the volume when turned on in Settings.
class ScheduledBackupJob < ApplicationJob
  queue_as :default

  def perform
    setting = Setting.instance
    InstanceBackup.store!(keep: setting.scheduled_backups_keep) if setting.scheduled_backups_enabled?
  end
end
