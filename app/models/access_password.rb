# Kamal Web has no user accounts: everyone signs in with KAMAL_WEB_PASSWORD, set
# in the .env Kamal Web is deployed with and passed on by .kamal/secrets.
# KAMAL_WEB_TOTP_SECRET adds a code from an authenticator app, and
# KAMAL_WEB_ALLOWED_IPS limits where the dashboard can be reached from.
# Changing any of them signs everybody out, because sessions are tied to a
# fingerprint of the password and the TOTP secret.
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
      "KAMAL_WEB_PASSWORD is not set. Add it to .env and run kamal deploy."
    elsif value.length < MINIMUM_LENGTH
      "KAMAL_WEB_PASSWORD must be at least #{MINIMUM_LENGTH} characters long. Change it in .env and run kamal deploy."
    elsif two_factor? && !Totp.valid_secret?(totp_secret)
      "KAMAL_WEB_TOTP_SECRET isn't a valid secret. Generate one with bin/totp-secret."
    elsif (invalid = invalid_networks).any?
      "KAMAL_WEB_ALLOWED_IPS has invalid entries: #{invalid.join(", ")}."
    end
  end

  def matches?(candidate, code: nil)
    problem.nil? && ActiveSupport::SecurityUtils.secure_compare(candidate.to_s, value) &&
      (!two_factor? || Totp.verify(totp_secret, code))
  end

  def fingerprint
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "kamal-web-session:#{value}:#{totp_secret}") if problem.nil?
  end

  def valid_fingerprint?(candidate)
    expected = fingerprint
    expected.present? && candidate.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(candidate, expected)
  end

  def invalid_networks
    ENV["KAMAL_WEB_ALLOWED_IPS"].to_s.split(/[\s,]+/).compact_blank.reject do |entry|
      IPAddr.new(entry)
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end
