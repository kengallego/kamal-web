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
