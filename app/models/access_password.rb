# Kamal Web has no user accounts: everyone signs in with KAMAL_WEB_PASSWORD, set
# in the .env Kamal Web is deployed with and passed on by .kamal/secrets.
# Changing it signs everybody out, because sessions are tied to a fingerprint
# of the password.
module AccessPassword
  MINIMUM_LENGTH = 12
  DEVELOPMENT_PASSWORD = "kamal-web-development".freeze

  module_function

  def value
    ENV["KAMAL_WEB_PASSWORD"].presence || (DEVELOPMENT_PASSWORD if Rails.env.local?)
  end

  # Why the configured password can't be used, if it can't.
  def problem
    if value.blank?
      "KAMAL_WEB_PASSWORD is not set. Add it to .env and run kamal deploy."
    elsif value.length < MINIMUM_LENGTH
      "KAMAL_WEB_PASSWORD must be at least #{MINIMUM_LENGTH} characters long. Change it in .env and run kamal deploy."
    end
  end

  def matches?(candidate)
    problem.nil? && ActiveSupport::SecurityUtils.secure_compare(candidate.to_s, value)
  end

  def fingerprint
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "kamal-web-session:#{value}") if problem.nil?
  end

  def valid_fingerprint?(candidate)
    expected = fingerprint
    expected.present? && candidate.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(candidate, expected)
  end
end
