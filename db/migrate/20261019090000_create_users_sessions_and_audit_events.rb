class CreateUsersSessionsAndAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.text :otp_secret
      t.datetime :last_signed_in_at
      t.timestamps
    end
    add_index :users, :email_address, unique: true

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end

    create_table :audit_events do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      # Who it was when it happened, kept after the account is deleted.
      t.string :actor, null: false
      t.string :action, null: false
      t.references :project, foreign_key: { on_delete: :nullify }
      t.string :subject_type
      t.integer :subject_id
      t.json :details, default: {}, null: false
      t.string :ip_address
      t.datetime :created_at, null: false
    end
    add_index :audit_events, :created_at

    add_reference :command_runs, :user, foreign_key: { on_delete: :nullify }
    add_reference :console_sessions, :user, foreign_key: { on_delete: :nullify }

    # Existing projects keep accepting their URL alone until the secret is
    # generated in project settings, so CI already using them doesn't break.
    add_column :projects, :deploy_webhook_secret, :string
  end
end
