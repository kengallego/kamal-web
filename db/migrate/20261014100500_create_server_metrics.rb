class CreateServerMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :server_metrics do |t|
      t.references :project, null: false, foreign_key: true
      t.string :host, null: false
      t.float :cpu_percent
      t.float :load_1
      t.float :load_5
      t.float :load_15
      t.integer :cpu_count
      t.bigint :memory_total
      t.bigint :memory_used
      t.bigint :disk_total
      t.bigint :disk_used
      t.json :containers, null: false, default: []
      t.text :error
      t.datetime :collected_at, null: false
    end
    add_index :server_metrics, [ :project_id, :host, :collected_at ]
  end
end
