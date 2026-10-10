# Time-based one-time passwords (RFC 6238, as used by authenticator apps):
# 6 digits, SHA-1, 30 second steps. Accepts the previous and next step to
# allow for clock drift, and each code only once.
module Totp
  STEP = 30
  DIGITS = 6
  BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".freeze

  module_function

  def generate_secret
    Array.new(32) { BASE32[SecureRandom.random_number(32)] }.join
  end

  def valid_secret?(secret)
    normalize(secret).then { |value| value.length >= 16 && value.delete(BASE32).empty? }
  end

  def code(secret, time = Time.current)
    code_for_step(secret, time.to_i / STEP)
  end

  def verify(secret, candidate, time: Time.current)
    candidate = candidate.to_s.gsub(/\s/, "")
    return false unless valid_secret?(secret) && candidate.match?(/\A\d{#{DIGITS}}\z/)

    current = time.to_i / STEP
    step = (current - 1..current + 1).find { |s| ActiveSupport::SecurityUtils.secure_compare(code_for_step(secret, s), candidate) }
    step.present? && Rails.cache.write("totp-used:#{step}:#{candidate}", true, unless_exist: true, expires_in: STEP * 3)
  end

  def provisioning_uri(secret, label)
    "otpauth://totp/#{ERB::Util.url_encode(label)}?secret=#{normalize(secret)}&issuer=Kamal%20Web"
  end

  def code_for_step(secret, step)
    hmac = OpenSSL::HMAC.digest("SHA1", decode(secret), [ step ].pack("Q>"))
    offset = hmac.bytes.last & 0x0f
    value = (hmac[offset, 4].unpack1("N") & 0x7fffffff) % (10**DIGITS)
    value.to_s.rjust(DIGITS, "0")
  end

  def normalize(secret)
    secret.to_s.upcase.delete(" =-")
  end

  def decode(secret)
    bits = normalize(secret).chars.map { |char| BASE32.index(char).to_s(2).rjust(5, "0") }.join
    [ bits[0, bits.length / 8 * 8] ].pack("B*")
  end
end
