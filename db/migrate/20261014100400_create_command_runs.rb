class CreateCommandRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :command_runs do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :destination
      t.string :kind, null: false
      t.json :options, null: false, default: {}
      t.string :status, null: false, default: "queued"
      t.string :trigger, null: false, default: "manual"
      t.integer :exit_code
      t.integer :pid
      t.text :output, null: false, default: ""
      t.string :git_revision
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
    add_index :command_runs, [ :project_id, :created_at ]
    add_index :command_runs, :status
  end
end
