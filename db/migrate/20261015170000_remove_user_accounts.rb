# Kamal UI signs in with a single KAMAL_UI_PASSWORD instead of user accounts.
class RemoveUserAccounts < ActiveRecord::Migration[8.1]
  def change
    remove_reference :command_runs, :user, index: true, type: :integer
    remove_reference :console_sessions, :user, index: true, type: :integer
    drop_table :sessions do |t|
      t.integer :user_id, null: false, index: true
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end
    drop_table :users do |t|
      t.string :email_address, null: false, index: { unique: true }
      t.string :password_digest, null: false
      t.string :name
      t.string :role, default: "viewer", null: false
      t.timestamps
    end
  end
end
