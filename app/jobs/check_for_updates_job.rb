require "net/http"

# Asks GitHub once a day for the latest Kamal Web release, so the sidebar can
# say when there's a newer one. Set KAMAL_WEB_UPDATE_CHECK=false to turn it off.
class CheckForUpdatesJob < ApplicationJob
  queue_as :default

  def self.enabled?
    ENV["KAMAL_WEB_UPDATE_CHECK"] != "false"
  end

  def perform
    return unless self.class.enabled?

    release = latest_release
    Setting.instance.update!(latest_version: release&.dig("tag_name")&.delete_prefix("v"), latest_version_url: release&.dig("html_url"), update_checked_at: Time.current)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, JSON::ParserError => error
    Rails.logger.info "Update check failed: #{error.class}: #{error.message}"
  end

  private
    def latest_release
      uri = URI("https://api.github.com/repos/#{KamalWeb::REPOSITORY}/releases/latest")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        http.get(uri.request_uri, "Accept" => "application/vnd.github+json", "User-Agent" => "KamalWeb/#{KamalWeb::VERSION}")
      end
      # 404 means the repository has no releases yet.
      JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
    end
end
