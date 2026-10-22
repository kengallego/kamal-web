require "rails_helper"

RSpec.describe Database do
  let(:server) { Server.find_or_create_by!(host: "192.0.2.10") }

  it "names a created container and generates its password" do
    database = Database.create!(name: "main", engine: "postgresql", source: "created", server: server, image: "postgres:17")

    expect(database).to have_attributes(container_name: "kamal-web-db-main", admin_user: "postgres", volume_name: "kamal-web-db-main")
    expect(database.password).to match(/\A\h{48}\z/)
    expect(Database.new(name: "Main DB", engine: "postgresql", source: "created", server: server, image: "postgres:17")).not_to be_valid
    expect(Database.new(name: "other", engine: "postgresql", source: "created", server: server, image: "mysql:8")).not_to be_valid
  end

  it "checks the scheme of an external URL" do
    expect(Database.new(name: "managed", engine: "postgresql", source: "external", url: "redis://example.com")).not_to be_valid
    expect(Database.create!(name: "managed", engine: "postgresql", source: "external", url: "postgres://doadmin:x@db.example.com:25060/defaultdb?sslmode=require").status).to eq("external")
  end

  describe "attachments" do
    let(:database) { Database.create!(name: "main", engine: "postgresql", source: "created", server: server, image: "postgres:17", status: "running") }
    let(:manager) { instance_double(DatabaseManager, create_user: "", remove_user: "", apply_firewall: "") }

    before { allow(DatabaseManager).to receive(:new).and_return(manager) }

    it "gives an app on the same server its own database over the kamal network" do
      project = create(:project, name: "shop")
      attachment = DatabaseAttachment.new(database: database, project: project, variable: "DATABASE_URL")

      expect(attachment.attach!).to be(true)
      expect(manager).to have_received(:create_user).with(attachment)
      expect(attachment).to have_attributes(database_name: "shop", username: "shop")
      expect(project.environment_for(nil)["DATABASE_URL"]).to eq("postgres://shop:#{attachment.password}@kamal-web-db-main:5432/shop")
      expect(manager).not_to have_received(:apply_firewall)
    end

    it "needs a published port for an app on another server, then connects over TLS" do
      project = create(:project, name: "shop", config_snapshots: { "production" => { "roles" => { "web" => [ "192.0.2.20" ] } } })
      attachment = DatabaseAttachment.new(database: database, project: project, destination: "production", variable: "DATABASE_URL")

      expect(attachment.attach!).to be(false)
      expect(attachment.errors[:base].first).to include("port for other servers")

      database.update!(public_port: 25432)
      attachment = DatabaseAttachment.new(database: database, project: project, destination: "production", variable: "DATABASE_URL")
      expect(attachment.attach!).to be(true), attachment.errors.full_messages.inspect
      expect(attachment.database_name).to eq("shop_production")
      expect(project.environment_for("production")["DATABASE_URL"]).to end_with("@192.0.2.10:25432/shop_production?sslmode=require")
      expect(database.remote_app_hosts).to eq([ "192.0.2.20" ])
      expect(manager).to have_received(:apply_firewall)
    end

    it "updates the stored URL when the database changes and removes it on detach" do
      project = create(:project, name: "shop", config_snapshots: { "" => { "roles" => { "web" => [ "192.0.2.20" ] } } })
      database.update!(public_port: 25432)
      attachment = DatabaseAttachment.new(database: database, project: project, variable: "DATABASE_URL")
      attachment.attach!

      database.update!(public_port: 25433)
      expect(project.reload.environment_for(nil)["DATABASE_URL"]).to include("192.0.2.10:25433")

      attachment.reload.detach!
      expect(manager).to have_received(:remove_user).with(attachment, delete_data: false)
      expect(project.environment_variables.reload).to be_empty
    end

    it "doesn't replace a variable the project already has" do
      project = create(:project)
      project.environment_variables.create!(key: "DATABASE_URL", value: "sqlite3:storage/production.sqlite3")

      attachment = DatabaseAttachment.new(database: database, project: project, variable: "DATABASE_URL")
      expect(attachment.attach!).to be(false)
      expect(attachment.errors[:variable]).to be_present
    end

    it "tells whether the app's config passes the variable on" do
      project = create(:project, config_snapshots: { "" => { "roles" => { "web" => [ "192.0.2.10" ] }, "raw" => { "env" => { "secret" => [ "RAILS_MASTER_KEY", "DATABASE_URL" ] } } } })
      expect(DatabaseAttachment.new(database: database, project: project, variable: "DATABASE_URL")).to be_listed_in_config
      expect(DatabaseAttachment.new(database: database, project: project, variable: "QUEUE_DATABASE_URL")).not_to be_listed_in_config
    end

    it "gives each Redis app its own database number" do
      redis = Database.create!(name: "cache", engine: "redis", source: "created", server: server, image: "valkey/valkey:8", status: "running")
      first, second = create(:project, name: "a"), create(:project, name: "b")

      DatabaseAttachment.new(database: redis, project: first, variable: "REDIS_URL").attach!
      DatabaseAttachment.new(database: redis, project: second, variable: "REDIS_URL").attach!

      expect(first.environment_for(nil)["REDIS_URL"]).to eq("redis://default:#{redis.password}@kamal-web-db-cache:6379/0")
      expect(second.environment_for(nil)["REDIS_URL"]).to end_with("/1")
      expect(manager).not_to have_received(:create_user)
    end

    it "passes an external URL on as it is" do
      managed = Database.create!(name: "managed", engine: "postgresql", source: "external", url: "postgres://doadmin:x@db.example.com:25060/defaultdb?sslmode=require")
      project = create(:project)

      expect(DatabaseAttachment.new(database: managed, project: project, variable: "DATABASE_URL").attach!).to be(true)
      expect(project.environment_for(nil)["DATABASE_URL"]).to eq(managed.url)
      expect(manager).not_to have_received(:create_user)
    end
  end
end
