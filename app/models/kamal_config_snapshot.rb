# Read-only view over the JSON produced by script/kamal_config_dump.rb.
class KamalConfigSnapshot
  attr_reader :data

  def initialize(data)
    @data = data || {}
  end

  def present?
    data.present? && error.blank?
  end

  def error
    data["error"]
  end

  def service
    data["service"]
  end

  def image
    data["image"]
  end

  def roles
    data.fetch("roles", {})
  end

  def accessories
    data.fetch("accessories", {})
  end

  def proxy_hosts
    data.fetch("proxy_hosts", [])
  end

  # Snapshots taken before these were recorded assume Kamal's defaults.
  def proxy_ssl?
    data.fetch("proxy_ssl", true) != false
  end

  def healthcheck_path
    data["healthcheck_path"].presence || "/up"
  end

  # What CheckAppHealthJob requests: each domain at the health check path.
  def health_check_urls
    proxy_hosts.reject { |host| host.include?("*") }.map { |host| "#{proxy_ssl? ? "https" : "http"}://#{host}#{healthcheck_path}" }
  end

  def ssh
    data.fetch("ssh", {})
  end

  def ssh_user
    ssh["user"].presence || "root"
  end

  def ssh_port
    (ssh["port"].presence || 22).to_i
  end

  def builder
    data.fetch("builder", {})
  end

  def primary_host
    data["primary_host"]
  end

  # Snapshots taken before primary_role was recorded fall back to Kamal's default.
  def primary_role
    data["primary_role"].presence || (roles.key?("web") ? "web" : roles.keys.first)
  end

  def all_hosts
    (roles.values.flatten + accessories.values.flatten).uniq
  end

  def raw_config
    data["raw"]
  end
end
