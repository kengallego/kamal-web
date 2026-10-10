class CreateConsoleSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :console_sessions do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :destination
      t.string :kind, null: false
      t.string :host
      t.datetime :started_at
      t.datetime :ended_at
      t.integer :exit_code

      t.timestamps
    end
  end
end
