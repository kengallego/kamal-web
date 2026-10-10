# Collects CPU, memory, disk, load and running containers from one host.
class ServerProbe
  SEPARATOR = "--kamal-web--".freeze

  SCRIPT = <<~SH.freeze
    head -1 /proc/stat; echo #{SEPARATOR}
    cat /proc/loadavg; echo #{SEPARATOR}
    nproc; echo #{SEPARATOR}
    free -b | awk '/^Mem:/ {print $2, $3}'; echo #{SEPARATOR}
    df -B1 -P / | awk 'NR==2 {print $2, $3}'; echo #{SEPARATOR}
    (docker ps --format '{{json .}}' 2>/dev/null || sudo -n docker ps --format '{{json .}}' 2>/dev/null); echo #{SEPARATOR}
    sleep 1; head -1 /proc/stat
  SH

  def initialize(project, host)
    @project = project
    @host = host
  end

  def collect
    attributes = parse(RemoteShell.new(@project, @host).run(SCRIPT))
    @project.server_metrics.create!(host: @host, collected_at: Time.current, **attributes)
  rescue RemoteShell::Error => error
    @project.server_metrics.create!(host: @host, collected_at: Time.current, error: error.message)
  end

  def parse(output)
    stat_before, loadavg, nproc, memory, disk, containers, stat_after = output.split("#{SEPARATOR}\n").map(&:strip)
    load_1, load_5, load_15 = loadavg.to_s.split.first(3).map(&:to_f)
    memory_total, memory_used = memory.to_s.split.map(&:to_i)
    disk_total, disk_used = disk.to_s.split.map(&:to_i)

    {
      cpu_percent: cpu_percent(stat_before, stat_after),
      load_1:, load_5:, load_15:,
      cpu_count: nproc.to_i.nonzero?,
      memory_total:, memory_used:, disk_total:, disk_used:,
      containers: parse_containers(containers)
    }
  end

  private
    def cpu_percent(before, after)
      first, second = [ before, after ].map { |line| line.to_s.split.drop(1).map(&:to_i) }
      return if first.empty? || second.empty?

      idle = (second[3] + second[4].to_i) - (first[3] + first[4].to_i)
      total = second.sum - first.sum
      ((1 - idle.to_f / total) * 100).round(1) if total.positive?
    end

    def parse_containers(output)
      output.to_s.lines.filter_map do |line|
        container = JSON.parse(line)
        container.slice("Names", "Image", "Status", "State", "RunningFor", "Ports")
      rescue JSON::ParserError
        nil
      end
    end
end
