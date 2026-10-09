class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.boolean :status_board_enabled, null: false, default: false
      t.string :status_board_token, null: false

      t.timestamps
    end
  end
end
