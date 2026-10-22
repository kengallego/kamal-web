require "rails_helper"

RSpec.describe DatabaseManager do
  let(:server) { Server.find_or_create_by!(host: "192.0.2.10") }
  let(:shell) { instance_double(RemoteShell) }

  before { allow(RemoteShell).to receive(:for_server).with(server).and_return(shell) }

  it "runs PostgreSQL with TLS, its data in a volume and the password in a file" do
    database = Database.create!(name: "main", engine: "postgresql", source: "created", server: server, image: "postgres:17", public_port: 25432)
    allow(shell).to receive(:run).and_return("")

    described_class.new(database).provision

    expect(shell).to have_received(:run) do |script, check:|
      expect(check).to be(true)
      expect(script).to include("--volume kamal-web-db-main:/var/lib/postgresql/data", "--network kamal", "--publish 0.0.0.0:25432:5432", %(--env-file "$dir/postgres.env"),
        "-c ssl=on", "pg_isready -q -h 127.0.0.1 -U postgres", %(echo #{Base64.strict_encode64("POSTGRES_PASSWORD=#{database.password}\n")}))
      expect(script).not_to include(database.password)
    end
  end

  it "keeps PostgreSQL 18 data where its image expects it" do
    database = Database.create!(name: "main", engine: "postgresql", source: "created", server: server, image: "postgres:18")
    allow(shell).to receive(:run).and_return("")

    described_class.new(database).provision

    expect(shell).to have_received(:run).with(a_string_including("--volume kamal-web-db-main:/var/lib/postgresql "), check: true)
  end

  it "sends SQL on stdin, so passwords stay out of the process list" do
    database = Database.create!(name: "main", engine: "postgresql", source: "created", server: server, image: "postgres:17")
    attachment = DatabaseAttachment.new(database: database, project: create(:project, name: "shop"), variable: "DATABASE_URL")
    attachment.valid?
    allow(shell).to receive(:run).and_return("")

    described_class.new(database).create_user(attachment)

    expect(shell).to have_received(:run).with(a_string_including("exec -i kamal-web-db-main psql") & satisfy { |script| !script.include?(attachment.password) },
      input: a_string_including(%(CREATE ROLE "shop" WITH LOGIN PASSWORD '#{attachment.password}'), %(CREATE DATABASE "shop" OWNER "shop"), %(REVOKE CONNECT, TEMPORARY ON DATABASE "shop" FROM PUBLIC)), check: true)
  end

  it "only lets the kamal network and the servers of remote apps reach the published port" do
    database = Database.create!(name: "main", engine: "postgresql", source: "created", server: server, image: "postgres:17", public_port: 25432)
    allow(database).to receive(:remote_app_hosts).and_return([ "192.0.2.20" ])
    allow(shell).to receive(:run).and_return("")

    described_class.new(database).apply_firewall

    expect(shell).to have_received(:run) do |script, check:|
      chain = "KAMAL-WEB-DB-#{database.id}"
      expect(script).to include("iptables -A #{chain} -s 192.0.2.20 -j RETURN", "iptables -A #{chain} -j DROP",
        "DOCKER-USER -p tcp -m conntrack --ctorigdstport 25432 --ctdir ORIGINAL -j #{chain}")
      expect(script.index("-s 192.0.2.20")).to be < script.index("-j DROP")
    end
  end

  it "reports the container's state" do
    database = Database.create!(name: "main", engine: "redis", source: "created", server: server, image: "valkey/valkey:8")
    allow(shell).to receive(:run).and_return("running\n")
    expect(described_class.new(database).status).to eq("running")

    allow(shell).to receive(:run).and_raise(RemoteShell::Error, "192.0.2.10: Connection refused")
    database.check!
    expect(database).to have_attributes(status: "failed", status_message: "192.0.2.10: Connection refused")
  end
end
