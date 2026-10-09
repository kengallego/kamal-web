Rails.application.configure do
  # SMTP is optional: password reset emails are only offered when it is set up.
  if ENV["SMTP_ADDRESS"].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV["SMTP_ADDRESS"],
      port: ENV.fetch("SMTP_PORT", 587).to_i,
      user_name: ENV["SMTP_USERNAME"].presence,
      password: ENV["SMTP_PASSWORD"].presence,
      authentication: ENV["SMTP_USERNAME"].present? ? :plain : nil,
      enable_starttls_auto: true
    }.compact
  end

  if (url = ENV["KAMAL_UI_URL"].presence)
    uri = URI.parse(url)
    config.action_mailer.default_url_options = { host: uri.host, port: uri.port, protocol: uri.scheme }
  end

  config.action_mailer.default_options = { from: ENV.fetch("MAILER_FROM", "Kamal UI <kamal-ui@localhost>") }
  config.x.password_reset_enabled = ENV["SMTP_ADDRESS"].present? || Rails.env.development?
end
