require "open3"
require "rubygems/package"

# Talks to the Docker daemon Kamal Web can reach directly (the host's, through
# the mounted /var/run/docker.sock). Used to discover Kamal apps on this server.
class LocalDocker
  class Error < StandardError; end

  TIMEOUT = 20

  def available?
    run("version", "--format", "{{.Server.Version}}").present?
  rescue Error
    false
  end

  # Full `docker inspect` data for every container carrying a Kamal "service" label.
  def kamal_containers
    ids = run("ps", "--all", "--quiet", "--no-trunc", "--filter", "label=service").split
    ids.empty? ? [] : JSON.parse(run("inspect", *ids))
  end

  def container(name)
    JSON.parse(run("inspect", "--type", "container", name)).first
  rescue Error, JSON::ParserError
    nil
  end

  def image_architecture(image)
    run("image", "inspect", "--format", "{{.Architecture}}", image).strip.presence
  rescue Error
    nil
  end

  # Starts a container in the background. +env+ holds the values of the
  # variables passed with a bare `--env NAME`, which keeps them off the command line.
  def start_container(*args, env: {})
    run("run", "--detach", *args, env: env).strip
  end

  def proxy_routes
    ProxyInspector.allocate.parse_routes(run("exec", "kamal-proxy", "kamal-proxy", "list"))
  rescue Error
    []
  end

  # Returns { "relative/path" => content } for the regular files under +path+
  # inside a container, read through `docker cp` so the image needs no shell.
  def read_files(container_id, path)
    tar = run("cp", "#{container_id}:#{path}", "-", binary: true)
    files = {}
    Gem::Package::TarReader.new(StringIO.new(tar)).each do |entry|
      next unless entry.file? && entry.header.size <= 1.megabyte

      files[entry.full_name] = entry.read.to_s.force_encoding(Encoding::UTF_8)
    end
    files
  rescue Error, Gem::Package::TarInvalidError
    {}
  end

  private
    def run(*args, binary: false, env: {})
      stdout, stderr, status = Timeout.timeout(TIMEOUT) do
        Open3.capture3(ProcessEnvironment.build(env), "docker", *args, binmode: binary, unsetenv_others: true)
      end
      raise Error, stderr.strip.presence || "docker #{args.first} failed" unless status.success?

      stdout
    rescue Errno::ENOENT
      raise Error, "The docker CLI is not installed"
    rescue Timeout::Error
      raise Error, "docker #{args.first} timed out"
    end
end
