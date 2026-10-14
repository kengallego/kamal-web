class AddAppUsageToMetrics < ActiveRecord::Migration[8.1]
  def change
    add_column :server_metrics, :app_cpu_percent, :float
    add_column :server_metrics, :app_memory_used, :bigint
    add_column :server_metrics, :app_disk_used, :bigint
    add_column :hourly_metrics, :app_cpu_percent, :float
    add_column :hourly_metrics, :app_memory_percent, :float
    add_column :hourly_metrics, :app_disk_percent, :float
  end
end
