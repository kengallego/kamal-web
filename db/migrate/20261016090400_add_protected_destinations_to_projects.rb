class AddProtectedDestinationsToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :protected_destinations, :json, null: false, default: []
  end
end
