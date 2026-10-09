class AddProfileToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name, :string
    add_column :users, :role, :string, null: false, default: "viewer"
  end
end
