class CreateDatabases < ActiveRecord::Migration[8.1]
  def change
    create_table :databases do |t|
      t.string :name, null: false
      t.string :engine, null: false
      t.string :source, null: false
      t.references :server, foreign_key: true
      t.string :container_name
      t.string :image
      t.string :admin_user
      t.text :password
      t.text :url
      t.integer :public_port
      t.string :status, default: "unknown", null: false
      t.text :status_message
      t.datetime :checked_at
      t.timestamps
    end
    add_index :databases, :name, unique: true
    add_index :databases, [ :server_id, :container_name ], unique: true, where: "container_name IS NOT NULL"

    create_table :database_attachments do |t|
      t.references :database, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.references :environment_variable, foreign_key: { on_delete: :nullify }
      t.string :destination
      t.string :variable, null: false
      t.string :database_name
      t.string :username
      t.text :password
      t.integer :redis_index
      t.timestamps
    end
    add_index :database_attachments, [ :project_id, :destination, :variable ], unique: true
    add_index :database_attachments, [ :database_id, :database_name ], unique: true, where: "database_name IS NOT NULL"
  end
end
