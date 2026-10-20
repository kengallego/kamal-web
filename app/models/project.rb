class Project < ApplicationRecord
  include RefreshesStatusBoard
  SOURCE_KINDS = %w[ git local discovered ].freeze
  # Commands that only start, stop or reroute existing containers, so they are
  # safe on a discovered project whose config was rebuilt without env or secrets.
  DISCOVERED_MUTATIONS = %w[ app_start app_stop app_maintenance app_live accessory_start accessory_stop accessory_restart ].freeze
  NOTIFICATION_FORMATS = %w[ generic slack discord ].freeze

  has_many :environment_variables, -> { order(:destination, :key) }, dependent: :destroy
  has_many :project_files, -> { order(:path) }, dependent: :destroy
  has_many :command_runs, dependent: :destroy
  has_many :console_sessions, dependent: :delete_all
  has_many :server_metrics, dependent: :delete_all
  has_many :hourly_metrics, dependent: :delete_all
  has_many :health_checks, dependent: :delete_all
  has_many :alerts, dependent: :delete_all

  has_secure_token :deploy_webhook_token, length: 36
  # Proves a deploy webhook call comes from CI or the git host, on top of the
  # URL's token. See DeployHooksController.
  has_secure_token :deploy_webhook_secret, length: 36, on: :create

  encrypts :ssh_private_key, :git_ssh_private_key, :git_access_token, :notification_webhook_url, :discovered_files, :deploy_webhook_secret

  normalizes :repository_url, :local_path, :branch, :config_file, with: ->(value) { value.strip.presence }

  validates :name, presence: true, uniqueness: true
  validates :source_kind, inclusion: { in: SOURCE_KINDS }
  validates :notification_format, inclusion: { in: NOTIFICATION_FORMATS }
  validates :branch, :config_file, presence: true
  validates :repository_url, presence: true, if: :git?
  validates :repository_url, format: { with: %r{\A(https://|ssh://|[\w.-]+@[\w.-]+:)\S+\z}, message: :invalid_git_url }, allow_blank: true
  validates :local_path, presence: true, if: :local?
  validates :discovered_service, presence: true, if: :discovered?
  validates :notification_webhook_url, format: { with: %r{\Ahttps?://\S+\z} }, allow_blank: true
  validate :config_file_is_relative
  validate :local_path_inside_projects_root, if: :local?
  validate :ssh_keys_are_private_keys

  scope :ordered, -> { order(:name) }

  after_save :register_servers, if: :saved_change_to_config_snapshots?
  after_destroy_commit :remove_clone
  after_destroy_commit :ignore_discovered_service, if: :discovered?

  def git?
    source_kind == "git"
  end

  def local?
    source_kind == "local"
  end

  def discovered?
    source_kind == "discovered"
  end

  def discovered_file_map
    JSON.parse(discovered_files.presence || "{}")
  end

  def allows_command?(command)
    !discovered? || !command.mutating? || command.key.in?(DISCOVERED_MUTATIONS)
  end

  def source_description
    if git? then "#{repository_url} · #{branch}"
    elsif local? then local_path
    else I18n.t("projects.form.kind_discovered")
    end
  end

  def workspace_path
    if local?
      Pathname.new(local_path)
    else
      Rails.configuration.x.workspaces_path.join("project-#{id}")
    end
  end

  # Destination names as found in the last config sync. The base config
  # (no -d flag) is represented by nil.
  def destinations
    config_snapshots.keys.sort.map(&:presence).presence || [ nil ]
  end

  def config_for(destination)
    KamalConfigSnapshot.new(config_snapshots[destination.to_s])
  end

  def hosts
    config_snapshots.values.flat_map { |snapshot| KamalConfigSnapshot.new(snapshot).all_hosts }.uniq
  end

  def register_servers
    Server.register(hosts)
  end

  # A host can serve several destinations, e.g. staging and production on
  # the same machine.
  def destinations_for_host(host)
    destinations.select { |destination| config_for(destination).all_hosts.include?(host) }
  end

  def destination_for_host(host)
    destinations_for_host(host).first
  end

  # Variables for the base config apply everywhere; destination-specific ones
  # override them.
  def environment_for(destination)
    variables = environment_variables.to_a
    base = variables.select { |variable| variable.destination.nil? }
    scoped = variables.select { |variable| destination.present? && variable.destination == destination }
    variables = (base + scoped).to_h { |variable| [ variable.key, variable.value.to_s ] }

    # A discovered project has no git checkout to take the version from.
    version = discovered? && discovered_versions[destination.to_s]
    version ? variables.reverse_merge("VERSION" => version) : variables
  end

  # Projects without their own key use the instance key from Settings.
  def ssh_keys
    [ ssh_private_key.presence || Setting.instance.ssh_private_key, git_ssh_private_key ].compact_blank
  end

  # Latest monitoring sample per host, which tells whether SSH works.
  def latest_metrics
    hosts.filter_map { |host| server_metrics.where(host: host).order(collected_at: :desc).first }
  end

  # Mutating commands on a protected destination need its name typed to run
  # from the browser. The base config is stored as "".
  def protected_destination?(destination)
    protected_destinations.include?(destination.to_s)
  end

  # Form checkboxes send "." for the base config, since "" is what an empty
  # selection sends.
  def protected_destinations=(names)
    super(Array(names).compact_blank.map { |name| name == "." ? "" : name.to_s }.uniq)
  end

  def confirmation_word(destination)
    destination.presence || name
  end

  def active_operation
    command_runs.active.find(&:mutating?)
  end

  def last_deploy(destination = :any)
    runs = command_runs.where(kind: %w[ deploy redeploy rollback setup ]).where.not(status: %w[ queued running ])
    runs = runs.where(destination: destination) unless destination == :any
    runs.order(created_at: :desc).first
  end

  LiveRelease = Data.define(:version, :created_at)

  # The version running for a destination, from the containers in the latest
  # monitoring samples, so apps deployed outside Kamal Web show up too.
  def live_release(destination, metrics = latest_metrics)
    config = config_for(destination)
    prefix = [ config.service, config.primary_role, destination.presence ].compact.join("-") + "-"
    container = metrics.reject(&:error).flat_map(&:containers).select do |container|
      labels = container["Labels"] || {}
      container["State"] == "running" && labels["service"] == config.service && labels["role"] == config.primary_role &&
        labels["destination"].to_s == destination.to_s && container["Names"].to_s.start_with?(prefix)
    end.max_by { |container| container["CreatedAt"].to_s }

    if container
      LiveRelease.new(version: container["Names"].delete_prefix(prefix), created_at: (Time.zone.parse(container["CreatedAt"].to_s) rescue nil))
    elsif discovered? && (version = discovered_versions[destination.to_s])
      LiveRelease.new(version: version, created_at: nil)
    end
  end

  private
    # Only clones made by Kamal Web are removed; mounted folders are left alone.
    def ignore_discovered_service
      Setting.instance.ignore_service!(discovered_service)
    end

    def remove_clone
      root = Rails.configuration.x.workspaces_path.expand_path
      FileUtils.rm_rf(root.join("project-#{id}")) unless local?
    end

    def config_file_is_relative
      if config_file.present? && (config_file.start_with?("/") || config_file.split("/").include?(".."))
        errors.add(:config_file, :not_relative)
      end
    end

    def local_path_inside_projects_root
      return if local_path.blank?

      root = Rails.configuration.x.projects_path.expand_path.to_s
      path = File.expand_path(local_path)
      unless path == root || path.start_with?("#{root}/")
        errors.add(:local_path, :outside_root, root: root)
      end
    end

    def ssh_keys_are_private_keys
      { ssh_private_key: ssh_private_key, git_ssh_private_key: git_ssh_private_key }.each do |attribute, key|
        next if key.blank?
        errors.add(attribute, :not_private_key) unless key.include?("PRIVATE KEY-----")
      end
    end
end
