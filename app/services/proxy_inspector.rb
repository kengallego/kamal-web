# Reads kamal-proxy's routes and recent access log from a host.
class ProxyInspector
  Route = Data.define(:service, :host, :path, :target, :state, :tls)
  Request = Data.define(:time, :host, :path, :method, :status, :duration_ms, :service, :remote_addr) do
    def status_class
      "#{status.to_i / 100}xx"
    end
  end

  def initialize(project, host)
    @shell = RemoteShell.new(project, host)
  end

  def routes
    output = @shell.run("docker exec kamal-proxy kamal-proxy list 2>&1 || sudo -n docker exec kamal-proxy kamal-proxy list 2>&1")
    parse_routes(output)
  end

  # Access log entries from the last window, newest first. Capped so a busy
  # proxy can't flood the page.
  def requests(window: 1.hour, limit: 20_000)
    since = "#{(window / 60).ceil}m"
    logs = "docker logs --since #{since} kamal-proxy 2>&1 || sudo -n docker logs --since #{since} kamal-proxy 2>&1"
    parse_requests(@shell.run("(#{logs}) | grep '\"msg\":\"Request\"' | tail -n #{limit.to_i}"))
  end

  def parse_routes(output)
    # kamal-proxy colors its table even without a TTY.
    lines = output.to_s.gsub(/\e\[[\d;]*m/, "").lines.map(&:rstrip).reject(&:blank?)
    header_index = lines.index { |line| line.match?(/\AService\s+Host/i) }
    return [] unless header_index

    header = lines[header_index]
    columns = header.enum_for(:scan, /\S+/).map { Regexp.last_match.begin(0) }

    lines.drop(header_index + 1).map do |line|
      values = columns.each_with_index.map do |start, index|
        finish = columns[index + 1] ? columns[index + 1] - start : nil
        (finish ? line[start, finish] : line[start..]).to_s.strip
      end
      Route.new(*values.fill("", values.size...6).first(6))
    end
  end

  def parse_requests(output)
    output.to_s.lines.filter_map do |line|
      entry = JSON.parse(line)
      next unless entry["msg"] == "Request"

      Request.new(
        time: (Time.zone.parse(entry["time"]) rescue nil),
        host: entry["host"], path: entry["path"], method: entry["method"],
        status: entry["status"].to_i, duration_ms: ((entry["duration"] || entry["dur"]).to_f / 1_000_000).round(1),
        service: entry["service"], remote_addr: entry["remote_addr"] || entry["client_addr"]
      )
    rescue JSON::ParserError
      nil
    end.reverse
  end
end
