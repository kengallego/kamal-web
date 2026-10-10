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
    [ config_check, *ssh_checks, proxy_check, app_check, secrets_check, repository_check ].compact
  end

  def failures?
    all.any?(&:failed?)
  end

  private
    def config_check
      if @project.sync_error.present?
        Check.new("Config", :failed, "The last sync failed: see above.")
      elsif !@config.present?
        Check.new("Config", :failed, @config.error.presence&.truncate(200) || "Not loaded yet. Press Sync.")
      else
        Check.new("Config", :ok, [ "#{@project.config_file} read", (ago(@project.synced_at) if @project.synced_at) ].compact.join(" "))
      end
    end

    def ssh_checks
      return [] unless @config.present?

      @config.all_hosts.map do |host|
        metric = @metrics[host]
        if metric.nil?
          Check.new("SSH to #{host}", :unknown, @project.monitoring_enabled? ? "Not checked yet. It's checked every minute." : "Monitoring is off, so this isn't checked.")
        elsif metric.error
          Check.new("SSH to #{host}", :failed, metric.error.truncate(200))
        else
          Check.new("SSH to #{host}", :ok, "Reached #{ago(metric.collected_at)}")
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
        Check.new("kamal-proxy", :failed, "Not running on #{missing.to_sentence}. Run Boot proxy from Commands.")
      else
        Check.new("kamal-proxy", :ok, "Running")
      end
    end

    def app_check
      return unless @config.present? && @config.service.present?

      prefix = [ @config.service, @config.primary_role, @destination.presence ].compact.join("-") + "-"
      host = @config.roles[@config.primary_role]&.first
      names = host && container_names(host)
      return unless names

      if names.any? { |name| name.start_with?(prefix) }
        Check.new("App", :ok, "Running on #{host}")
      else
        Check.new("App", :failed, "No #{@config.primary_role} container running on #{host}. Deploy, or Start app from Commands.")
      end
    end

    def secrets_check
      return if @project.discovered?

      files = [ ".kamal/secrets-common", ".kamal/secrets", (".kamal/secrets.#{@destination}" if @destination.present?) ].compact
        .map { |file| @project.workspace_path.join(file) }.select(&:file?)
      return Check.new("Secrets", :ok, "No .kamal/secrets file") if files.empty?

      defined = @project.environment_for(@destination).keys + PROVIDED
      wanted = files.flat_map { |file| file.read.lines.reject { |line| line.lstrip.start_with?("#") }.flat_map { |line| line.scan(/\$\{?([A-Z_][A-Z0-9_]*)/).flatten } }.uniq
      missing = wanted - defined
      if missing.any?
        Check.new("Secrets", :failed, "#{missing.join(", ")} #{missing.one? ? "isn't" : "aren't"} set. Add #{missing.one? ? "it" : "them"} under Settings → Environment variables.")
      else
        Check.new("Secrets", :ok, "Every variable .kamal/secrets reads is set")
      end
    end

    def repository_check
      return unless @project.discovered?

      Check.new("Repository", :unknown, "Detected from the server. Add the git repository to deploy and roll back.")
    end

    # kamal-proxy runs next to the primary role, which is what serves traffic.
    def proxy_hosts
      @config.present? ? Array(@config.roles[@config.primary_role]) : []
    end

    def ago(time)
      "#{ApplicationController.helpers.time_ago_in_words(time)} ago"
    end

    def container_names(host)
      metric = @metrics[host]
      return if metric.nil? || metric.error

      metric.containers.map { |container| container["Names"].to_s.delete_prefix("/") }
    end
end
