class CreateHealthChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :health_checks do |t|
      t.references :project, null: false, foreign_key: true
      t.string :url, null: false
      t.integer :status_code
      t.float :duration_ms
      t.text :error
      t.datetime :certificate_expires_at
      t.datetime :checked_at, null: false
    end
    add_index :health_checks, %i[ project_id url checked_at ]
  end
end
