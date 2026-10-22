require "rails_helper"

RSpec.describe "Databases" do
  let(:server) { Server.find_or_create_by!(host: "192.0.2.10") }
  let(:manager) { instance_double(DatabaseManager, create_user: "", remove_user: "", apply_firewall: "", status: "running", remove: "") }

  before do
    sign_in
    allow(DatabaseManager).to receive(:new).and_return(manager)
  end

  it "creates a database on a server in the background" do
    post databases_path, params: { database: { source: "created", engine: "postgresql", name: "main", server_id: server.id, image: "postgres:17", container_name: "ignored" } }

    database = Database.find_by!(name: "main")
    expect(response).to redirect_to(database_path(database))
    expect(database).to have_attributes(status: "provisioning", container_name: "kamal-web-db-main")
    expect(ProvisionDatabaseJob).to have_been_enqueued.with(database)

    get databases_path
    expect(response.body).to include("main", "PostgreSQL", "starting")
  end

  it "registers an existing container and checks it" do
    post databases_path, params: { database: { source: "existing", engine: "redis", name: "cache", server_id: server.id, container_name: "shop-redis" } }

    expect(Database.find_by!(name: "cache")).to have_attributes(status: "running", container_name: "shop-redis")
  end

  it "attaches an app and detaches it" do
    database = Database.create!(name: "main", engine: "postgresql", source: "created", server: server, image: "postgres:17", status: "running")
    project = create(:project, name: "shop")

    get database_path(database)
    expect(response.body).to include("shop")

    post database_attachments_path(database), params: { database_attachment: { target: "#{project.id}/", variable: "" } }
    expect(response).to redirect_to(database_path(database))
    expect(flash[:notice]).to include("DATABASE_URL")
    expect(project.environment_variables.pluck(:key)).to eq([ "DATABASE_URL" ])
    expect(AuditEvent.last.action).to eq("databases/attachments#create")

    get project_settings_path(project)
    expect(response.body).to include(database_path(database), "DATABASE_URL")

    get database_path(database)
    expect(response.body).to include("env.secret")

    delete database_path(database)
    expect(flash[:alert]).to be_present
    expect(Database.exists?(database.id)).to be(true)

    attachment = database.attachments.first
    delete database_attachment_path(database, attachment), params: { delete_data: "1" }
    expect(manager).to have_received(:remove_user).with(attachment, delete_data: true)
    expect(project.environment_variables.reload).to be_empty
  end

  it "shows why an attachment failed" do
    database = Database.create!(name: "main", engine: "postgresql", source: "created", server: server, image: "postgres:17", status: "running")
    project = create(:project)
    allow(manager).to receive(:create_user).and_raise(RemoteShell::Error, "192.0.2.10: permission denied")

    post database_attachments_path(database), params: { database_attachment: { target: "#{project.id}/", variable: "DATABASE_URL" } }

    expect(flash[:alert]).to include("permission denied")
    expect(database.attachments).to be_empty
    expect(project.environment_variables).to be_empty
  end

  it "deletes a created database with or without its volume" do
    database = Database.create!(name: "main", engine: "postgresql", source: "created", server: server, image: "postgres:17")

    delete database_path(database), params: { delete_data: "1" }

    expect(response).to redirect_to(databases_path)
    expect(manager).to have_received(:remove).with(delete_data: true)
    expect(Database.count).to eq(0)
  end

  it "publishes another port by running the container again" do
    database = Database.create!(name: "main", engine: "postgresql", source: "created", server: server, image: "postgres:17", status: "running")

    patch database_path(database), params: { database: { name: "main", public_port: "25432", image: "postgres:18" } }

    expect(database.reload).to have_attributes(public_port: 25432, image: "postgres:17", status: "provisioning")
    expect(ProvisionDatabaseJob).to have_been_enqueued.with(database)
  end
end
