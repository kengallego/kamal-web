class Project < ApplicationRecord
  SOURCE_KINDS = %w[ git local ].freeze
  NOTIFICATION_FORMATS = %w[ generic slack discord ].freeze

  has_many :environment_variables, -> { order(:destination, :key) }, dependent: :destroy
  has_many :project_files, -> { order(:path) }, dependent: :destroy
  has_many :command_runs, dependent: :destroy
  has_many :server_metrics, dependent: :delete_all

  has_secure_token :deploy_webhook_token, length: 36

  encrypts :ssh_private_key, :git_ssh_private_key, :git_access_token, :notification_webhook_url

  normalizes :repository_url, :local_path, :branch, :config_file, with: ->(value) { value.strip.presence }

  validates :name, presence: true, uniqueness: true
  validates :source_kind, inclusion: { in: SOURCE_KINDS }
  validates :notification_format, inclusion: { in: NOTIFICATION_FORMATS }
  validates :branch, :config_file, presence: true
  validates :repository_url, presence: true, if: :git?
  validates :repository_url, format: { with: %r{\A(https://|ssh://|[\w.-]+@[\w.-]+:)\S+\z}, message: "must be an https or ssh git URL" }, allow_blank: true
  validates :local_path, presence: true, if: :local?
  validates :notification_webhook_url, format: { with: %r{\Ahttps?://\S+\z} }, allow_blank: true
  validate :config_file_is_relative
  validate :local_path_inside_projects_root, if: :local?
  validate :ssh_keys_are_private_keys

  scope :ordered, -> { order(:name) }

  after_destroy_commit :remove_clone

  def git?
    source_kind == "git"
  end

  def local?
    source_kind == "local"
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

  # Variables for the base config apply everywhere; destination-specific ones
  # override them.
  def environment_for(destination)
    variables = environment_variables.to_a
    base = variables.select { |variable| variable.destination.nil? }
    scoped = variables.select { |variable| destination.present? && variable.destination == destination }
    (base + scoped).to_h { |variable| [ variable.key, variable.value.to_s ] }
  end

  def ssh_keys
    [ ssh_private_key, git_ssh_private_key ].compact_blank
  end

  def active_operation
    command_runs.active.find(&:mutating?)
  end

  def last_deploy(destination = :any)
    runs = command_runs.where(kind: %w[ deploy redeploy rollback setup ]).where.not(status: %w[ queued running ])
    runs = runs.where(destination: destination) unless destination == :any
    runs.order(created_at: :desc).first
  end

  def rollback_candidates(destination)
    command_runs.succeeded.where(kind: %w[ deploy redeploy ], destination: destination)
      .where.not(git_revision: nil).order(created_at: :desc).distinct.limit(20).pluck(:git_revision).uniq
  end

  private
    # Only clones made by Kamal UI are removed; mounted folders are left alone.
    def remove_clone
      root = Rails.configuration.x.workspaces_path.expand_path
      FileUtils.rm_rf(root.join("project-#{id}")) if git?
    end

    def config_file_is_relative
      if config_file.present? && (config_file.start_with?("/") || config_file.split("/").include?(".."))
        errors.add(:config_file, "must be relative to the project root")
      end
    end

    def local_path_inside_projects_root
      return if local_path.blank?

      root = Rails.configuration.x.projects_path.expand_path.to_s
      path = File.expand_path(local_path)
      unless path == root || path.start_with?("#{root}/")
        errors.add(:local_path, "must be inside #{root} (mount your projects there)")
      end
    end

    def ssh_keys_are_private_keys
      { ssh_private_key: ssh_private_key, git_ssh_private_key: git_ssh_private_key }.each do |attribute, key|
        next if key.blank?
        errors.add(attribute, "doesn't look like a private key") unless key.include?("PRIVATE KEY-----")
      end
    end
end
