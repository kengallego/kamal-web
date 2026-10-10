require "shellwords"

# The containers of an app (not its accessories) on each of its hosts, read
# over SSH. Shown next to a running deploy so old and new versions can be seen
# starting and stopping.
class ServiceContainers
  Container = Data.define(:host, :name, :role, :state, :status, :created_at) do
    def running?
      state == "running"
    end
  end

  def initialize(project, destination)
    @project = project
    @destination = destination
    @config = project.config_for(destination)
  end

  def hosts
    @config.roles.values.flatten.uniq
  end

  # Returns [containers, errors by host].
  def call
    errors = {}
    containers = hosts.map do |host|
      Thread.new do
        parse(host, RemoteShell.new(@project, host, destination: @destination).run(command))
      rescue RemoteShell::Error => error
        errors[host] = error.message
        []
      end
    end.flat_map(&:value)
    [ containers.sort_by { |container| [ container.host, container.running? ? 0 : 1, -(container.created_at&.to_i || 0) ] }, errors ]
  end

  def command
    labels = { service: @config.service, destination: @destination.to_s }
    raise RemoteShell::Error, "Unexpected characters in the Kamal config" unless labels.values.all? { |value| value.to_s.match?(ServerReleases::SAFE) }

    filters = labels.map { |key, value| "--filter label=#{key}=#{value}" }.join(" ")
    format = Shellwords.escape("{{.Names}}\t{{.Label \"role\"}}\t{{.State}}\t{{.Status}}\t{{.CreatedAt}}")
    "docker ps -a #{filters} --format #{format} 2>&1 || sudo -n docker ps -a #{filters} --format #{format} 2>&1"
  end

  def parse(host, output)
    output.to_s.lines.filter_map do |line|
      name, role, state, status, created = line.chomp.split("\t")
      next if role.blank?

      Container.new(host: host, name: name, role: role, state: state, status: status, created_at: (Time.zone.parse(created.to_s) rescue nil))
    end
  end
end
