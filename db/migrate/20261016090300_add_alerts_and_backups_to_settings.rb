class AddAlertsAndBackupsToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :alert_disk_percent, :integer, null: false, default: 90
    add_column :settings, :alert_memory_percent, :integer, null: false, default: 90
    add_column :settings, :scheduled_backups_enabled, :boolean, null: false, default: false
    add_column :settings, :scheduled_backups_keep, :integer, null: false, default: 7
  end
end
