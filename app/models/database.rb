# A PostgreSQL or Redis server that apps can be attached to. Kamal Web either
# runs it in a container on one of the servers ("created"), uses a container
# that is already there ("existing", such as a Kamal accessory) or only knows
# its URL ("external", such as a DigitalOcean managed database).
class Database < ApplicationRecord
  ENGINES = %w[ postgresql redis ].freeze
  SOURCES = %w[ created existing external ].freeze
  IMAGES = {
    "postgresql" => %w[ postgres:18 postgres:17 postgres:16 ],
    "redis" => %w[ valkey/valkey:8 redis:7 ]
  }.freeze
  PORTS = { "postgresql" => 5432, "redis" => 6379 }.freeze
  VARIABLES = { "postgresql" => "DATABASE_URL", "redis" => "REDIS_URL" }.freeze
  URL_SCHEMES = { "postgresql" => %w[ postgres postgresql ], "redis" => %w[ redis rediss ] }.freeze

  belongs_to :server, optional: true
  has_many :attachments, class_name: "DatabaseAttachment", dependent: :restrict_with_error

  encrypts :password, :url

  normalizes :name, :container_name, :admin_user, :url, with: ->(value) { value.strip.presence }

  validates :name, presence: true, uniqueness: { case_sensitive: false }, format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }, length: { maximum: 40 }
  validates :engine, inclusion: { in: ENGINES }
  validates :source, inclusion: { in: SOURCES }
  validates :server, presence: true, unless: :external?
  validates :container_name, presence: true, format: { with: /\A[\w.-]+\z/ }, unless: :external?
  validates :container_name, uniqueness: { scope: :server_id }, allow_nil: true
  validates :image, inclusion: { in: ->(database) { IMAGES.fetch(database.engine, []) } }, if: :created?
  validates :admin_user, format: { with: /\A\w+\z/ }, allow_nil: true
  validates :public_port, numericality: { only_integer: true, in: 1024..65_535 }, allow_nil: true
  validates :url, presence: true, if: :external?
  validate :url_matches_engine, if: -> { external? && url.present? }

  before_validation :set_defaults, on: :create

  after_update_commit :refresh_attachments, if: -> { saved_change_to_public_port? || saved_change_to_url? || saved_change_to_password? }
  broadcasts_refreshes

  scope :ordered, -> { order(:name) }

  ENGINES.each { |name| define_method(:"#{name}?") { engine == name } }
  SOURCES.each { |name| define_method(:"#{name}?") { source == name } }

  def default_variable
    VARIABLES.fetch(engine)
  end

  def internal_port
    PORTS.fetch(engine)
  end

  def volume_name
    container_name if created?
  end

  # Where the server keeps the files the container mounts.
  def files_directory
    "$HOME/.kamal-web/databases/#{container_name}"
  end

  # A created container serves PostgreSQL over TLS with its own certificate,
  # so apps on other servers connect with sslmode=require.
  def tls?
    created? && postgresql?
  end

  # Redis servers have one shared password; PostgreSQL gets a user per app.
  def shared_password
    password if redis?
  end

  def address_for(app_hosts)
    if external?
      nil
    elsif app_hosts.all? { |host| host == server.host }
      [ container_name, internal_port ]
    elsif public_port
      [ server.host, public_port ]
    end
  end

  def manager
    DatabaseManager.new(self)
  end

  # Runs the container. Called from ProvisionDatabaseJob, since pulling the
  # image can take a while.
  def provision!
    update!(status: "provisioning", status_message: nil)
    manager.provision
    update!(status: "running", status_message: nil, checked_at: Time.current)
    manager.apply_firewall if public_port
  rescue RemoteShell::Error, DatabaseManager::Error => error
    update!(status: "failed", status_message: error.message, checked_at: Time.current)
  end

  def check!
    status = manager.status
    manager.apply_firewall if created? && public_port && status == "running"
    update!(status: status, status_message: nil, checked_at: Time.current)
  rescue RemoteShell::Error, DatabaseManager::Error => error
    update!(status: "failed", status_message: error.message, checked_at: Time.current)
  end

  # Hosts of apps on other servers, which the firewall lets in.
  def remote_app_hosts
    attachments.includes(:project).flat_map(&:app_hosts).uniq - [ server&.host ]
  end

  def remove!(delete_data: false)
    manager.remove(delete_data: delete_data) if created?
    destroy!
  end

  private
    def set_defaults
      self.container_name ||= "kamal-web-db-#{name}" if created?
      self.admin_user ||= "postgres" if postgresql? && !external?
      self.password ||= SecureRandom.hex(24) if created?
      self.status = "external" if external?
    end

    def url_matches_engine
      scheme = URI.parse(url).scheme
      errors.add(:url, :wrong_scheme, schemes: URL_SCHEMES.fetch(engine, []).join(", ")) unless scheme.in?(URL_SCHEMES.fetch(engine, []))
    rescue URI::InvalidURIError
      errors.add(:url, :invalid)
    end

    def refresh_attachments
      attachments.reload.each(&:write_variable!)
    end
end
