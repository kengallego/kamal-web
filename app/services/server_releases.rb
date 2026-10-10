require "shellwords"

# The versions of an app that Kamal still keeps on its primary host: the
# running container plus the stopped ones left by earlier deploys. Kamal can
# only roll back to a version whose container still exists.
class ServerReleases
  Release = Data.define(:version, :state, :created_at, :current) do
    def running?
      state == "running"
    end
  end

  SAFE = /\A[\w.-]*\z/

  def initialize(project, destination)
    @project = project
    @destination = destination
    @config = project.config_for(destination)
  end

  def host
    @config.roles[role]&.first || @config.primary_host
  end

  def role
    @config.primary_role
  end

  def call
    return [] if host.blank?

    parse(RemoteShell.new(@project, host, destination: @destination).run(command))
  end

  def command
    labels = { service: @config.service, role: role, destination: @destination.to_s }
    raise RemoteShell::Error, "Unexpected characters in the Kamal config" unless labels.values.all? { |value| value.to_s.match?(SAFE) }

    filters = labels.map { |key, value| "--filter label=#{key}=#{value}" }.join(" ")
    format = Shellwords.escape("{{.Names}}\t{{.State}}\t{{.CreatedAt}}")
    "docker ps -a #{filters} --format #{format} 2>&1 || sudo -n docker ps -a #{filters} --format #{format} 2>&1"
  end

  def parse(output)
    prefix = [ @config.service, role, @destination.presence ].compact.join("-") + "-"
    releases = output.to_s.lines.filter_map do |line|
      name, state, created = line.chomp.split("\t")
      # Kamal renames the container it replaces during a rollback.
      next unless name&.start_with?(prefix) && !name.include?("_replaced_")

      Release.new(version: name.delete_prefix(prefix), state: state, created_at: (Time.zone.parse(created.to_s) rescue nil), current: false)
    end
    releases = releases.sort_by { |release| release.created_at || Time.at(0) }.reverse
    current = releases.find(&:running?)
    releases.map { |release| release.with(current: release.equal?(current)) }
  end
end
