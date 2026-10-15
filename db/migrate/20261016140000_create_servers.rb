class CreateServers < ActiveRecord::Migration[8.1]
  def up
    create_table :servers do |t|
      t.string :host, null: false
      t.string :name
      t.string :ssh_user
      t.integer :ssh_port
      t.text :notes
      t.datetime :checked_at
      t.text :check_error
      t.string :system_info
      t.timestamps
    end
    add_index :servers, :host, unique: true

    # Hosts already in synced configs become servers right away.
    Server.reset_column_information
    Project.find_each(&:register_servers)
  end

  def down
    drop_table :servers
  end
end
