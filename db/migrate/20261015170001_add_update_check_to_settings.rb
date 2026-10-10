class AddUpdateCheckToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :latest_version, :string
    add_column :settings, :latest_version_url, :string
    add_column :settings, :update_checked_at, :datetime
  end
end
