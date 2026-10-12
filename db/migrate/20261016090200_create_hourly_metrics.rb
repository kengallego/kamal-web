class CreateHourlyMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :hourly_metrics do |t|
      t.references :project, null: false, foreign_key: true
      t.string :host, null: false
      t.datetime :hour, null: false
      t.float :cpu_percent
      t.float :load_percent
      t.float :memory_percent
      t.float :disk_percent
      t.integer :samples, null: false, default: 0
    end
    add_index :hourly_metrics, %i[ project_id host hour ], unique: true
  end
end
