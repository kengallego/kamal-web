class Projects::MonitoringController < Projects::BaseController
  RANGES = { "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days }.freeze

  def show
    @range = RANGES.key?(params[:range]) ? params[:range] : RANGES.keys.first
    @samples = @project.server_metrics.recent.order(:collected_at).group_by(&:host)
    # Past a day the history comes from the hourly averages.
    @history = if @range == "24h"
      @samples
    else
      @project.hourly_metrics.where(hour: RANGES[@range].ago..).order(:hour).group_by(&:host)
    end
    @hosts = (@project.hosts + @samples.keys).uniq
  end

  # Collects a fresh sample from every host right away.
  def create
    if @project.ssh_keys.empty?
      redirect_to project_monitoring_path(@project), alert: t("flash.monitoring.no_key")
    else
      @project.hosts.each { |host| ServerProbe.new(@project, host).collect }
      redirect_to project_monitoring_path(@project), notice: t("flash.monitoring.refreshed")
    end
  end
end
