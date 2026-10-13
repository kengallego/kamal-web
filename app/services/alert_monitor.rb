# Opens and resolves a project's alerts from what monitoring collected. Host
# alerts need a few samples in a row, so a single slow SSH connection or a
# short memory spike doesn't page anyone.
class AlertMonitor
  SAMPLES = 3
  CERTIFICATE_DAYS = 14
  PROXY_WINDOW = 5.minutes
  PROXY_MIN_REQUESTS = 20
  PROXY_ERROR_RATE = 0.1

  def initialize(project)
    @project = project
    @setting = Setting.instance
  end

  def check_hosts
    @project.hosts.each do |host|
      samples = @project.server_metrics.where(host: host).order(collected_at: :desc).limit(SAMPLES).to_a
      next if samples.empty?

      latest = samples.first
      track "host_unreachable", host, consecutive(samples) { |sample| sample.error }, latest.error&.truncate(300)
      next if latest.error

      track "disk", host, latest.disk_percent.to_f >= @setting.alert_disk_percent, percent(latest.disk_percent)
      track "memory", host, consecutive(samples) { |sample| sample.memory_percent.to_f >= @setting.alert_memory_percent }, percent(latest.memory_percent)
    end
    check_apps
  end

  def check_health(checks)
    unavailable, available = @project.destinations.partition { |destination| unavailable_on_purpose?(destination) }
    suppressed_urls = unavailable.flat_map { |destination| @project.config_for(destination).health_check_urls } -
      available.flat_map { |destination| @project.config_for(destination).health_check_urls }

    checks.each do |check|
      previous = @project.health_checks.where(url: check.url).where.not(id: check.id).order(checked_at: :desc).first
      failing = if check.up? || suppressed_urls.include?(check.url) then false
      elsif previous && !previous.up? then true
      end
      track "health_check", check.url, failing, check.error&.truncate(300) || "HTTP #{check.status_code}"

      if (days = check.certificate_days_left)
        track "certificate", URI(check.url).host, days < CERTIFICATE_DAYS, I18n.t("alerts.days_left", count: days)
      end
    end
  end

  # 5xx responses from kamal-proxy for this app over the last few minutes.
  def check_proxy
    @project.destinations.each do |destination|
      config = @project.config_for(destination)
      host = config.roles[config.primary_role]&.first
      next unless config.present? && config.proxy_hosts.any? && host

      if unavailable_on_purpose?(destination)
        track "proxy_errors", subject(host, destination), false, nil
        next
      end

      services = config.roles.keys.map { |role| [ config.service, role, destination.presence ].compact.join("-") }
      requests = ProxyInspector.new(@project, host).requests(window: PROXY_WINDOW, limit: 5_000)
        .select { |request| services.include?(request.service) && request.time.to_i >= PROXY_WINDOW.ago.to_i }
      errors = requests.count { |request| request.status >= 500 }
      failing = requests.size >= PROXY_MIN_REQUESTS && errors >= requests.size * PROXY_ERROR_RATE
      track "proxy_errors", subject(host, destination), failing, "#{errors}/#{requests.size}"
    rescue RemoteShell::Error
      # Unreachable hosts have their own alert.
    end
  end

  private
    def track(kind, subject, failing, message)
      Alert.track(@project, kind, subject, failing: failing, message: message)
    end

    # true when every recent sample fails, false once the latest passes, and
    # nil (no change) while it's still undecided.
    def consecutive(samples, &failing)
      if !failing.call(samples.first) then false
      elsif samples.size == SAMPLES && samples.all?(&failing) then true
      end
    end

    # The app's primary role should have a container on each of its hosts,
    # unless it was stopped or put into maintenance from Kamal Web.
    def check_apps
      @project.destinations.each do |destination|
        config = @project.config_for(destination)
        next unless config.present? && config.service.present?

        prefix = [ config.service, config.primary_role, destination.presence ].compact.join("-") + "-"
        unavailable = unavailable_on_purpose?(destination)

        Array(config.roles[config.primary_role]).each do |host|
          if unavailable
            track "app_down", subject(host, destination), false, nil
            next
          end

          samples = @project.server_metrics.where(host: host).order(collected_at: :desc).limit(2).to_a
          next if samples.size < 2 || samples.any?(&:error)

          running = samples.map { |sample| sample.containers.any? { |container| container["Names"].to_s.delete_prefix("/").start_with?(prefix) } }
          failing = if running.first then false
          elsif running.none? then true
          end
          track "app_down", subject(host, destination), failing, nil
        end
      end
    end

    def unavailable_on_purpose?(destination)
      runs = @project.command_runs.where(destination: destination)
      return true if runs.where(status: "running", kind: %w[ app_stop app_maintenance ]).exists?

      succeeded = runs.succeeded.order(created_at: :desc, id: :desc)
      stopped = succeeded.where(kind: %w[ app_stop app_start app_boot deploy redeploy rollback setup ]).first
      maintenance = succeeded.where(kind: %w[ app_maintenance app_live app_boot deploy redeploy rollback setup ]).first
      stopped&.kind == "app_stop" || maintenance&.kind == "app_maintenance"
    end

    def subject(host, destination)
      destination.present? ? "#{host} (#{destination})" : host
    end

    def percent(value)
      "#{value.round}%" if value
    end
end
