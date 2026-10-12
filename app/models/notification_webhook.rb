require "net/http"

# The webhook a project's notifications are posted to: Slack and Discord get
# a line of text, anything else the structured JSON.
module NotificationWebhook
  ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED ].freeze

  module_function

  def payload(project, text:, json:)
    case project.notification_format
    when "slack" then { text: text }
    when "discord" then { content: text }
    else json
    end
  end

  def deliver(project, payload)
    url = project.notification_webhook_url
    return if url.blank?

    uri = URI.parse(url)
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "User-Agent" => "KamalWeb")
    request.body = payload.to_json

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end
  end

  # Links back to Kamal Web need to know where it is served.
  def url(path)
    host = ENV["KAMAL_WEB_URL"].presence
    "#{host.chomp("/")}#{path}" if host
  end
end
