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
    sleep 1; head -1 /proc/stat; echo #{SEPARATOR}
  SH

  def initialize(project, host)
    @project = project
    @host = host
  end

  def collect
    attributes = parse(RemoteShell.new(@project, @host).run(SCRIPT + container_script))
    @project.server_metrics.create!(host: @host, collected_at: Time.current, **attributes)
  rescue RemoteShell::Error => error
    @project.server_metrics.create!(host: @host, collected_at: Time.current, error: error.message)
  end

  def parse(output)
    stat_before, loadavg, nproc, memory, disk, containers, stat_after, stats, sizes, mounts = output.split("#{SEPARATOR}\n").map(&:strip)
    load_1, load_5, load_15 = loadavg.to_s.split.first(3).map(&:to_f)
    memory_total, memory_used = memory.to_s.split.map(&:to_i)
    disk_total, disk_used = disk.to_s.split.map(&:to_i)

    {
      cpu_percent: cpu_percent(stat_before, stat_after),
      load_1:, load_5:, load_15:,
      cpu_count: nproc.to_i.nonzero?,
      memory_total:, memory_used:, disk_total:, disk_used:,
      containers: parse_containers(containers),
      **app_usage(stats, sizes, mounts, nproc.to_i)
    }
  end

  private
    # Exact Kamal service labels include every role/destination and configured
    # accessories, without counting the shared proxy or another app's containers.
    def container_script
      services = @project.config_snapshots.values.flat_map do |snapshot|
        config = KamalConfigSnapshot.new(snapshot)
        next [] unless config.service.present?

        accessories = config.accessories.keys.map do |name|
          snapshot.dig("raw", "accessories", name, "service").presence || "#{config.service}-#{name}"
        end
        [ config.service, *accessories ]
      end.uniq
      filters = services.map { |service| "--filter #{Shellwords.escape("label=service=#{service}")}" }.join(" ")
      return "" if services.empty?

      <<~SH
        docker_cmd() { docker "$@" 2>/dev/null || sudo -n docker "$@" 2>/dev/null; }
        ids=$(docker_cmd ps -aq #{filters}) || exit 0
        if [ -z "$ids" ]; then
          echo ok; echo #{SEPARATOR}; echo ok; echo #{SEPARATOR}; echo 0
          exit 0
        fi
        running=$(docker_cmd ps -q #{filters}) || exit 0
        if [ -z "$running" ]; then echo ok; else
          docker_cmd stats --no-stream --format '{{json .}}' $running && echo ok
        fi
        echo #{SEPARATOR}
        docker_cmd inspect --size --format '{"SizeRw":{{json .SizeRw}}}' $ids && echo ok
        echo #{SEPARATOR}
        paths=$(docker_cmd inspect --format '{{println .LogPath}}{{range .Mounts}}{{if .RW}}{{if or (eq .Type "volume") (eq .Type "bind")}}{{println .Source}}{{end}}{{end}}{{end}}' $ids) || exit 0
        if [ -z "$paths" ]; then echo 0; else
          printf '%s\\n' "$paths" | sed '/^$/d' | sort -u | while IFS= read -r path; do
            if usage=$(du -sk -- "$path" 2>/dev/null) || usage=$(sudo -n du -sk -- "$path" 2>/dev/null); then
              printf '%s\\n' "$usage"
            else echo unavailable; fi
          done | awk '/^unavailable$/ {failed=1} {total+=$1} END {if (!failed) printf "%.0f\\n", total * 1024}'
        fi
      SH
    end

    def app_usage(stats, sizes, mounts, cores)
      usage = {}
      if stats.to_s.lines.last&.strip == "ok"
        rows = json_lines(stats)
        cpu = rows.map { |row| Float(row.fetch("CPUPerc").delete_suffix("%")) }
        memory = rows.map { |row| bytes(row.fetch("MemUsage").split(" / ").first) }
        usage[:app_cpu_percent] = (cpu.sum / cores).round(1) if cores.positive?
        usage[:app_memory_used] = memory.sum if memory.none?(nil)
      end
      if sizes.to_s.lines.last&.strip == "ok" && mounts.to_s.match?(/\A\d+\z/)
        writable = json_lines(sizes).map { |row| row["SizeRw"] }
        usage[:app_disk_used] = writable.sum + mounts.to_i if writable.none?(nil)
      end
      usage
    rescue KeyError, ArgumentError, JSON::ParserError
      # Missing Docker statistics must stay unknown, rather than become zero.
      {}
    end

    def json_lines(output)
      output.lines.reject { |line| line.strip == "ok" }.map { |line| JSON.parse(line) }
    end

    def bytes(value)
      match = value.to_s.match(/\A([\d.]+)\s*(B|kB|KB|KiB|MB|MiB|GB|GiB|TB|TiB)\z/)
      return unless match

      unit = match[2]
      power = { "B" => 0, "k" => 1, "K" => 1, "M" => 2, "G" => 3, "T" => 4 }.fetch(unit[0])
      (match[1].to_f * (unit.include?("i") ? 1024 : 1000)**power).round
    end

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
        # Kamal's labels tell which app version and destination each container runs.
        labels = container["Labels"].to_s.split(",").to_h { |pair| pair.split("=", 2) }.slice("service", "role", "destination")
        container.slice("Names", "Image", "Status", "State", "RunningFor", "Ports", "CreatedAt").merge("Labels" => labels)
      rescue JSON::ParserError
        nil
      end
    end
end
