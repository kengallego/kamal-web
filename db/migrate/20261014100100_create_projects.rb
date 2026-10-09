class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name, null: false
      t.string :source_kind, null: false, default: "git"
      t.string :repository_url
      t.string :branch, null: false, default: "main"
      t.string :local_path
      t.string :config_file, null: false, default: "config/deploy.yml"
      t.text :ssh_private_key
      t.text :git_ssh_private_key
      t.text :git_access_token
      t.string :deploy_webhook_token, null: false
      t.string :notification_webhook_url
      t.string :notification_format, null: false, default: "generic"
      t.boolean :monitoring_enabled, null: false, default: true
      t.json :config_snapshots, null: false, default: {}
      t.string :git_revision
      t.datetime :synced_at
      t.text :sync_error

      t.timestamps
    end
    add_index :projects, :name, unique: true
    add_index :projects, :deploy_webhook_token, unique: true
  end
end
