class AddAutoUpdateToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :auto_update_enabled, :boolean, null: false, default: false
    add_column :settings, :auto_update_version, :string
    add_column :settings, :auto_update_status, :string
    add_column :settings, :auto_update_started_at, :datetime
    add_column :settings, :auto_update_finished_at, :datetime
    add_column :settings, :auto_update_output, :text
  end
end
