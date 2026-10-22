require "shellwords"

# Runs a database's container on its server and manages what lives in it,
# over SSH with the server's access. Docker and iptables run through sudo
# when the SSH user isn't root.
class DatabaseManager
  class Error < StandardError; end

  PRELUDE = <<~SH.freeze
    set -e
    if [ "$(id -u)" = 0 ]; then S=; else S="sudo -n"; fi
    if docker info >/dev/null 2>&1; then D=docker; else D="$S docker"; fi
  SH

  CERTIFICATE_PATH = "/etc/kamal-web".freeze
  # The uid both the postgres and redis/valkey images run as.
  IMAGE_UID = 999

  def initialize(database)
    @database = database
  end

  def provision
    run(<<~SH)
      dir="#{@database.files_directory}"
      mkdir -p "$dir" && chmod 700 "$dir"
      umask 077
      #{write_files}
      $S chown #{IMAGE_UID}:#{IMAGE_UID} #{mounted_files.keys.map { |name| %("$dir/#{name}") }.join(" ")}
      $D network create kamal >/dev/null 2>&1 || true
      $D pull -q #{q @database.image} >/dev/null
      $D rm -f #{q container} >/dev/null 2>&1 || true
      $D run --detach --name #{q container} --network kamal --restart unless-stopped \\
        --label kamal-web.database=#{q @database.name} --log-opt max-size=10m \\
        --volume #{q @database.volume_name}:#{data_path} \\
        #{%(--env-file "$dir/postgres.env") if @database.postgresql?} \\
        #{mounted_files.keys.map { |name| %(--volume "$dir/#{name}:#{CERTIFICATE_PATH}/#{name}:ro") }.join(" ")} \\
        #{"--publish 0.0.0.0:#{@database.public_port}:#{@database.internal_port}" if @database.public_port} \\
        #{q @database.image} #{command} >/dev/null
      for i in $(seq 60); do
        if #{ready_check}; then exit 0; fi
        sleep 1
      done
      $D logs --tail 20 #{q container} 2>&1
      echo "The database didn't start within a minute."
      exit 1
    SH
  end

  # running, stopped or missing for containers; reachable or unreachable for
  # external databases, from a TCP connection.
  def status
    return external_status if @database.external?

    run(<<~SH).lines.last.to_s.strip
      state=$($D inspect -f '{{.State.Status}}' #{q container} 2>/dev/null) || { echo missing; exit 0; }
      if [ "$state" = running ] && #{ready_check}; then echo running; else echo stopped; fi
    SH
  end

  # Other apps' users can't connect to the database: PUBLIC can by default.
  def create_user(attachment)
    psql(<<~SQL)
      DO $$BEGIN
        IF EXISTS (SELECT FROM pg_roles WHERE rolname = '#{attachment.username}') THEN
          ALTER ROLE "#{attachment.username}" WITH LOGIN PASSWORD '#{attachment.password}';
        ELSE
          CREATE ROLE "#{attachment.username}" WITH LOGIN PASSWORD '#{attachment.password}';
        END IF;
      END$$;
      SELECT 'CREATE DATABASE "#{attachment.database_name}" OWNER "#{attachment.username}"' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '#{attachment.database_name}')\\gexec
      REVOKE CONNECT, TEMPORARY ON DATABASE "#{attachment.database_name}" FROM PUBLIC;
    SQL
  end

  def remove_user(attachment, delete_data: false)
    if delete_data
      psql(<<~SQL)
        DROP DATABASE IF EXISTS "#{attachment.database_name}" WITH (FORCE);
        DROP ROLE IF EXISTS "#{attachment.username}";
      SQL
    else
      psql(<<~SQL)
        DO $$BEGIN
          IF EXISTS (SELECT FROM pg_roles WHERE rolname = '#{attachment.username}') THEN
            ALTER ROLE "#{attachment.username}" WITH NOLOGIN;
          END IF;
        END$$;
        SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = '#{attachment.username}';
      SQL
    end
  end

  # Only the hosts of attached apps on other servers (and containers on the
  # kamal network) reach the published port. Docker's DOCKER-USER chain sees
  # the packets before they are forwarded to the container. The rules don't
  # survive a reboot, so CheckDatabasesJob applies them again.
  def apply_firewall
    accepted = @database.remote_app_hosts.map { |host| "$S iptables -A #{chain} -s #{q host} -j RETURN" }
    run(<<~SH)
      $S iptables -N #{chain} 2>/dev/null || $S iptables -F #{chain}
      subnet=$($D network inspect kamal -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null | awk '{print $1}')
      [ -n "$subnet" ] && $S iptables -A #{chain} -s "$subnet" -j RETURN
      #{accepted.join("\n")}
      $S iptables -A #{chain} -j DROP
      #{firewall_rule("-C")} 2>/dev/null || #{firewall_rule("-I")}
    SH
  end

  def remove(delete_data: false)
    run(<<~SH)
      $D rm -f #{q container} >/dev/null 2>&1 || true
      #{"$D volume rm #{q @database.volume_name} >/dev/null 2>&1 || true" if delete_data}
      rm -rf "#{@database.files_directory}"
      while #{firewall_rule("-D")} 2>/dev/null; do :; done
      $S iptables -F #{chain} 2>/dev/null || true
      $S iptables -X #{chain} 2>/dev/null || true
    SH
  end

  private
    def run(script, input: nil)
      shell = RemoteShell.for_server(@database.server)
      if input
        shell.run(PRELUDE + script, input: input, check: true)
      else
        shell.run(PRELUDE + script, check: true)
      end
    end

    def psql(sql)
      command = "$D exec -i #{q container} psql -X -q -v ON_ERROR_STOP=1 -U #{q @database.admin_user} -d postgres"
      run(command, input: sql)
    end

    def external_status
      uri = URI.parse(@database.url)
      Socket.tcp(uri.host, uri.port || @database.internal_port, connect_timeout: 5).close
      "reachable"
    rescue SystemCallError, SocketError, IOError, URI::InvalidURIError
      "unreachable"
    end

    def container
      @database.container_name
    end

    def chain
      "KAMAL-WEB-DB-#{@database.id}"
    end

    def firewall_rule(action)
      "$S iptables #{action} DOCKER-USER -p tcp -m conntrack --ctorigdstport #{@database.public_port.to_i} --ctdir ORIGINAL -j #{chain}"
    end

    def q(value)
      Shellwords.escape(value.to_s)
    end

    def data_path
      if @database.postgresql?
        # PostgreSQL 18 images keep their data one level up, by major version.
        @database.image.split(":").last.to_i >= 18 ? "/var/lib/postgresql" : "/var/lib/postgresql/data"
      else
        "/data"
      end
    end

    # Files the container mounts, owned by the image's user.
    def mounted_files
      @mounted_files ||=
        if @database.postgresql?
          key, certificate = self.class.certificate(@database.container_name)
          { "server.key" => key, "server.crt" => certificate }
        else
          { "redis.conf" => "requirepass #{@database.password}\nappendonly yes\n" }
        end
    end

    # Written to the server with umask 077, from base64 so the content never
    # needs quoting.
    def write_files
      files = mounted_files
      files = files.merge("postgres.env" => "POSTGRES_PASSWORD=#{@database.password}\n") if @database.postgresql?
      files.map { |name, content| %(echo #{Base64.strict_encode64(content)} | base64 -d > "$dir/#{name}") }.join("\n")
    end

    def command
      if @database.postgresql?
        "-c ssl=on -c ssl_cert_file=#{CERTIFICATE_PATH}/server.crt -c ssl_key_file=#{CERTIFICATE_PATH}/server.key"
      else
        "#{server_binary} #{CERTIFICATE_PATH}/redis.conf"
      end
    end

    def server_binary
      @database.image.start_with?("valkey") ? "valkey-server" : "redis-server"
    end

    # NOAUTH also means Redis is up: the password isn't needed to know that.
    def ready_check
      if @database.postgresql?
        "$D exec #{q container} pg_isready -q -h 127.0.0.1 -U #{q @database.admin_user} >/dev/null 2>&1"
      else
        "$D exec #{q container} sh -c 'valkey-cli ping 2>/dev/null || redis-cli ping' 2>/dev/null | grep -qE 'PONG|NOAUTH'"
      end
    end

    class << self
      # A self-signed certificate: apps use sslmode=require, which encrypts
      # without verifying it.
      def certificate(name)
        key = OpenSSL::PKey::EC.generate("prime256v1")
        certificate = OpenSSL::X509::Certificate.new
        certificate.version = 2
        certificate.serial = SecureRandom.random_number(2**64)
        certificate.subject = certificate.issuer = OpenSSL::X509::Name.parse("/CN=#{name}")
        certificate.public_key = key
        certificate.not_before = Time.current
        certificate.not_after = 10.years.from_now
        certificate.sign(key, OpenSSL::Digest::SHA256.new)
        [ key.to_pem, certificate.to_pem ]
      end
    end
end
