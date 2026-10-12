# The checklist on a project's overview: what Kamal needs to work, from what
# Kamal Web already knows (the last config sync and the latest monitoring
# samples), so it costs no SSH round trip.
class ProjectChecks
  Check = Data.define(:label, :status, :detail) do
    def ok? = status == :ok
    def failed? = status == :failed
  end

  # ENV entries a .kamal/secrets file may use without them being stored in Kamal Web.
  PROVIDED = %w[ HOME PATH USER PWD KAMAL_DESTINATION KAMAL_VERSION ].freeze

  def initialize(project, destination, latest_metrics)
    @project = project
    @destination = destination
    @config = project.config_for(destination)
    @metrics = latest_metrics
  end

  def all
    [ config_check, *ssh_checks, proxy_check, app_check, *health_checks, secrets_check, repository_check ].compact
  end

  def failures?
    all.any?(&:failed?)
  end

  private
    def config_check
      if @project.sync_error.present?
        Check.new(t("config"), :failed, t("config_sync_failed"))
      elsif !@config.present?
        Check.new(t("config"), :failed, @config.error.presence&.truncate(200) || t("config_not_loaded"))
      else
        Check.new(t("config"), :ok, @project.synced_at ? t("config_read_at", file: @project.config_file, time: ago(@project.synced_at)) : t("config_read", file: @project.config_file))
      end
    end

    def ssh_checks
      return [] unless @config.present?

      @config.all_hosts.map do |host|
        metric = @metrics[host]
        if metric.nil?
          Check.new(t("ssh", host: host), :unknown, @project.monitoring_enabled? ? t("ssh_pending") : t("ssh_monitoring_off"))
        elsif metric.error
          Check.new(t("ssh", host: host), :failed, metric.error.truncate(200))
        else
          Check.new(t("ssh", host: host), :ok, t("ssh_ok", time: ago(metric.collected_at)))
        end
      end
    end

    def proxy_check
      hosts = proxy_hosts
      return if hosts.empty?

      known = hosts.select { |host| container_names(host) }
      return if known.empty?

      missing = known.reject { |host| container_names(host).include?("kamal-proxy") }
      if missing.any?
        Check.new("kamal-proxy", :failed, t("proxy_down", hosts: missing.to_sentence))
      else
        Check.new("kamal-proxy", :ok, t("running"))
      end
    end

    def app_check
      return unless @config.present? && @config.service.present?

      prefix = [ @config.service, @config.primary_role, @destination.presence ].compact.join("-") + "-"
      host = @config.roles[@config.primary_role]&.first
      names = host && container_names(host)
      return unless names

      if names.any? { |name| name.start_with?(prefix) }
        Check.new(t("app"), :ok, t("app_running", host: host))
      else
        Check.new(t("app"), :failed, t("app_down", role: @config.primary_role, host: host))
      end
    end

    # From CheckAppHealthJob, which requests each domain every minute.
    def health_checks
      return [] unless @config.present?

      urls = @config.health_check_urls
      latest = @project.health_checks.latest_per_url.where(url: urls).index_by(&:url)

      urls.map do |url|
        check = latest[url]
        label = t("health", url: url.sub(%r{\Ahttps?://}, ""))
        if check.nil?
          Check.new(label, :unknown, @project.monitoring_enabled? ? t("health_pending") : t("ssh_monitoring_off"))
        elsif check.up?
          Check.new(label, :ok, [ t("health_ok", status: check.status_code, ms: check.duration_ms.round, uptime: uptime(url)), certificate(check) ].compact.join(" · "))
        else
          Check.new(label, :failed, check.error&.truncate(200) || t("health_status", status: check.status_code))
        end
      end
    end

    def uptime(url)
      checks = @project.health_checks.recent.where(url: url)
      total = checks.count
      up = checks.where(error: nil, status_code: 200..399).count
      total.zero? ? "–" : "#{(up * 100.0 / total).floor(1)}%"
    end

    def certificate(check)
      days = check.certificate_days_left
      t("certificate", count: days) if days
    end

    def secrets_check
      return if @project.discovered?

      files = [ ".kamal/secrets-common", ".kamal/secrets", (".kamal/secrets.#{@destination}" if @destination.present?) ].compact
        .map { |file| @project.workspace_path.join(file) }.select(&:file?)
      return Check.new(t("secrets"), :ok, t("secrets_none")) if files.empty?

      defined = @project.environment_for(@destination).keys + PROVIDED
      wanted = files.flat_map { |file| file.read.lines.reject { |line| line.lstrip.start_with?("#") }.flat_map { |line| line.scan(/\$\{?([A-Z_][A-Z0-9_]*)/).flatten } }.uniq
      missing = wanted - defined
      if missing.any?
        Check.new(t("secrets"), :failed, t("secrets_missing", count: missing.size, names: missing.join(", ")))
      else
        Check.new(t("secrets"), :ok, t("secrets_ok"))
      end
    end

    def repository_check
      return unless @project.discovered?

      Check.new(t("repository"), :unknown, t("repository_missing"))
    end

    # kamal-proxy runs next to the primary role, which is what serves traffic.
    def proxy_hosts
      @config.present? ? Array(@config.roles[@config.primary_role]) : []
    end

    def ago(time)
      I18n.t("common.ago", time: ApplicationController.helpers.time_ago_in_words(time))
    end

    def t(key, **options)
      I18n.t("checks.#{key}", **options)
    end

    def container_names(host)
      metric = @metrics[host]
      return if metric.nil? || metric.error

      metric.containers.map { |container| container["Names"].to_s.delete_prefix("/") }
    end
end
