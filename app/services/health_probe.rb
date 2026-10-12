require "net/http"

# Requests each of an app's domains at its health check path, the way a
# visitor reaches it, and notes when the TLS certificate expires.
class HealthProbe
  TIMEOUT = 10

  def initialize(project)
    @project = project
  end

  def urls
    @project.destinations.flat_map { |destination| @project.config_for(destination).health_check_urls }.uniq
  end

  def call
    urls.map { |url| check(url) }
  end

  def check(url)
    uri = URI(url)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    attributes = {}

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT, ssl_timeout: TIMEOUT) do |http|
      response = http.request(Net::HTTP::Get.new(uri, "User-Agent" => "KamalWeb/#{KamalWeb::VERSION} health check"))
      attributes = { status_code: response.code.to_i, certificate_expires_at: http.peer_cert&.not_after }
    end
    record(url, started, **attributes)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError, EOFError => error
    record(url, started, error: "#{error.class.name.demodulize}: #{error.message}".truncate(300))
  end

  private
    def record(url, started, **attributes)
      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
      @project.health_checks.create!(url: url, checked_at: Time.current, duration_ms: duration, **attributes)
    end
end
