class AddDiscoveryToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :discovered_service, :string
    add_column :projects, :discovered_files, :text
    add_column :projects, :discovered_versions, :json, default: {}, null: false
    add_index :projects, :discovered_service, unique: true, where: "discovered_service IS NOT NULL"

    add_column :settings, :ssh_private_key, :text
    add_column :settings, :ssh_public_key, :text
    add_column :settings, :ignored_services, :json, default: [], null: false
  end
end
