# A machine Kamal Web knows about. Hosts in a project's Kamal config are
# registered automatically on every sync; others can be added by hand before
# anything is deployed to them. The config stays the source of truth for
# deploys: this is only the inventory, with SSH overrides for checks.
class Server < ApplicationRecord
  CHECK_SCRIPT = "uname -srm; docker --version 2>/dev/null || sudo -n docker --version 2>/dev/null || echo 'Docker not installed'".freeze

  normalizes :host, :name, :ssh_user, with: ->(value) { value.strip.presence }

  validates :host, presence: true, uniqueness: { case_sensitive: false }, format: { with: /\A[\w.:\[\]-]+\z/ }
  validates :ssh_port, numericality: { only_integer: true, in: 1..65_535 }, allow_nil: true
  validate :host_unchanged_while_in_use, on: :update

  scope :ordered, -> { order(Arel.sql("LOWER(COALESCE(name, host))")) }

  def self.register(hosts)
    hosts.each { |host| find_or_create_by!(host: host) }
  end

  def label
    name.presence || host
  end

  def projects
    Project.ordered.select { |project| project.hosts.include?(host) }
  end

  def in_use?
    projects.any?
  end

  # The SSH user and port come from the first project deploying here, unless
  # the server overrides them.
  def effective_ssh_user
    ssh_user.presence || config&.ssh_user || "root"
  end

  def effective_ssh_port
    ssh_port || config&.ssh_port || 22
  end

  def ssh_keys
    [ Setting.instance.ssh_private_key, *projects.map(&:ssh_private_key) ].compact_blank.uniq
  end

  # Latest monitoring sample per project deploying here.
  def latest_metrics
    ServerMetric.where(id: ServerMetric.recent.where(host: host).group(:project_id).select("MAX(id)")).includes(:project).to_a
  end

  # The most recent thing known about SSH access: a manual check or a
  # monitoring sample.
  def connection
    sample = ServerMetric.where(host: host).order(collected_at: :desc).first
    if sample && (checked_at.nil? || sample.collected_at > checked_at)
      Connection.new(ok: sample.error.nil?, error: sample.error, at: sample.collected_at)
    elsif checked_at
      Connection.new(ok: check_error.nil?, error: check_error, at: checked_at)
    end
  end

  Connection = Data.define(:ok, :error, :at)

  def check!
    output = RemoteShell.for_server(self).run(CHECK_SCRIPT)
    update!(checked_at: Time.current, check_error: nil, system_info: output.lines.map(&:strip).compact_blank.join(" · ").truncate(255))
  rescue RemoteShell::Error => error
    update!(checked_at: Time.current, check_error: error.message)
  end

  private
    def config
      project = projects.first
      project&.config_for(project.destination_for_host(host))
    end

    def host_unchanged_while_in_use
      errors.add(:host, :in_use) if host_changed? && Server.find(id).in_use?
    end
end
