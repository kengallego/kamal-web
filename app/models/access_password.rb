# The instance's own access settings, from the .env Kamal Web is deployed with
# and passed on by .kamal/secrets. KAMAL_WEB_PASSWORD creates the first account
# (see SetupsController) and lets nobody in once one exists.
# KAMAL_WEB_TOTP_SECRET adds a code from an authenticator app to that, and to
# signing in to accounts without one of their own. KAMAL_WEB_ALLOWED_IPS limits
# where the dashboard can be reached from.
module AccessPassword
  MINIMUM_LENGTH = 12
  DEVELOPMENT_PASSWORD = "kamal-web-development".freeze

  module_function

  def value
    ENV["KAMAL_WEB_PASSWORD"].presence || (DEVELOPMENT_PASSWORD if Rails.env.local?)
  end

  def totp_secret
    ENV["KAMAL_WEB_TOTP_SECRET"].presence
  end

  def two_factor?
    totp_secret.present?
  end

  def allowed_networks
    ENV["KAMAL_WEB_ALLOWED_IPS"].to_s.split(/[\s,]+/).compact_blank.map { |entry| IPAddr.new(entry) }
  end

  def allowed_ip?(ip)
    networks = allowed_networks
    networks.empty? || networks.any? { |network| network.include?(ip) }
  rescue IPAddr::InvalidAddressError
    false
  end

  # Why Kamal Web can't let anyone in with the current settings, if it can't.
  def problem
    if value.blank?
      I18n.t("access_password.missing")
    elsif value.length < MINIMUM_LENGTH
      I18n.t("access_password.too_short", count: MINIMUM_LENGTH)
    elsif two_factor? && !Totp.valid_secret?(totp_secret)
      I18n.t("access_password.invalid_totp")
    elsif (invalid = invalid_networks).any?
      I18n.t("access_password.invalid_ips", entries: invalid.join(", "))
    end
  end

  def matches?(candidate, code: nil)
    problem.nil? && ActiveSupport::SecurityUtils.secure_compare(candidate.to_s, value) &&
      (!two_factor? || Totp.verify(totp_secret, code))
  end


  def invalid_networks
    ENV["KAMAL_WEB_ALLOWED_IPS"].to_s.split(/[\s,]+/).compact_blank.reject do |entry|
      IPAddr.new(entry)
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end
