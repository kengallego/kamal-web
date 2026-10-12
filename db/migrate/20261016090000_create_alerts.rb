class CreateAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :alerts do |t|
      t.references :project, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :subject, null: false, default: ""
      t.text :message
      t.datetime :opened_at, null: false
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :alerts, %i[ project_id kind subject ], unique: true, where: "resolved_at IS NULL", name: "index_alerts_open"
  end
end
