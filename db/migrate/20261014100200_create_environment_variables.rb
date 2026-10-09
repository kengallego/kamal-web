class CreateEnvironmentVariables < ActiveRecord::Migration[8.1]
  def change
    create_table :environment_variables do |t|
      t.references :project, null: false, foreign_key: true
      t.string :key, null: false
      t.text :value
      t.string :destination

      t.timestamps
    end
    add_index :environment_variables, [ :project_id, :destination, :key ], unique: true
  end
end
