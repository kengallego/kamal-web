# Gives a project (or one of its destinations) a database: its own database
# and user on a PostgreSQL server, a database number on a Redis server, or
# the URL of an external one. The URL is stored as one of the project's
# environment variables, which .kamal/secrets passes to the app on deploy.
class DatabaseAttachment < ApplicationRecord
  REDIS_DATABASES = 16

  belongs_to :database
  belongs_to :project
  belongs_to :environment_variable, optional: true

  encrypts :password

  normalizes :destination, with: ->(value) { value.presence }
  normalizes :variable, with: ->(value) { value.strip.upcase.presence }

  validates :variable, presence: true, format: { with: /\A[A-Z_][A-Z0-9_]*\z/, message: :invalid_name }
  validates :variable, uniqueness: { scope: [ :project_id, :destination ] }
  validates :database_name, uniqueness: { scope: :database_id }, allow_nil: true
  validate :destination_configured
  validate :variable_free, on: :create
  validate :reachable, on: :create
  validate :redis_database_free, on: :create

  before_validation :set_credentials, on: :create

  # Creates what the app needs on the database server and stores the URL.
  def attach!
    transaction do
      save!
      database.manager.create_user(self) if database.postgresql? && !database.external?
      write_variable!
    end
    database.manager.apply_firewall if database.created? && database.public_port
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  # With delete_data the app's database and user are dropped. Otherwise they
  # stay, but the user can no longer sign in.
  def detach!(delete_data: false)
    transaction do
      environment_variable&.destroy!
      destroy!
      database.manager.remove_user(self, delete_data: delete_data) if database.postgresql? && !database.external?
    end
    database.manager.apply_firewall if database.created? && database.public_port
  end

  def write_variable!
    variable_record = environment_variable || project.environment_variables.new(key: variable, destination: destination)
    variable_record.update!(value: url)
    update_column(:environment_variable_id, variable_record.id) unless environment_variable_id == variable_record.id
  end

  # The hosts the app's containers run on.
  def app_hosts
    destinations = destination ? [ destination ] : project.destinations
    destinations.flat_map { |name| project.config_for(name).roles.values.flatten }.uniq
  end

  def remote?
    database.address_for(app_hosts)&.first == database.server&.host
  end

  def url
    return database.url if database.external?

    host, port = database.address_for(app_hosts)
    if database.postgresql?
      query = "?sslmode=require" if database.tls? && remote?
      "postgres://#{username}:#{password}@#{host}:#{port}/#{database_name}#{query}"
    else
      # Redis 6+ (every image Kamal Web creates) has a "default" user; some
      # clients send an empty one as a user name.
      credentials = "#{"default" if database.created?}:#{CGI.escape(database.shared_password)}@" if database.shared_password.present?
      "redis://#{credentials}#{host}:#{port}/#{redis_index}"
    end
  end

  # Kamal only passes variables listed under env.secret to the app.
  def listed_in_config?
    destinations = destination ? [ destination ] : project.destinations
    destinations.all? do |name|
      raw = project.config_for(name).raw_config || {}
      envs = [ raw["env"], *raw.fetch("servers", {}).then { |servers| servers.is_a?(Hash) ? servers.values : [] }.map { |role| role["env"] if role.is_a?(Hash) } ]
      envs.compact.any? { |env| env.is_a?(Hash) && Array(env["secret"]).any? { |name| name.to_s.split(":").first == variable } }
    end
  end

  private
    def set_credentials
      return unless database

      if database.postgresql? && !database.external?
        self.database_name ||= [ project&.name, destination, (variable unless variable == "DATABASE_URL") ].compact.join("_").downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "").first(63)
        self.username ||= database_name
        self.password ||= SecureRandom.hex(24)
      elsif database.redis? && !database.external?
        used = database.attachments.pluck(:redis_index)
        self.redis_index ||= (0...REDIS_DATABASES).find { |index| !used.include?(index) }
      end
    end

    def destination_configured
      errors.add(:destination, :unknown) if destination && project && !project.destinations.include?(destination)
    end

    def variable_free
      return unless project && variable

      if project.environment_variables.exists?(key: variable, destination: destination)
        errors.add(:variable, :taken_by_variable)
      end
    end

    def reachable
      return if database.nil? || project.nil? || database.external?

      errors.add(:base, :not_reachable, port: database.internal_port) unless database.address_for(app_hosts)
      errors.add(:base, :not_running) unless database.status == "running"
    end

    def redis_database_free
      errors.add(:base, :no_redis_database) if database&.redis? && !database.external? && redis_index.nil?
    end
end
