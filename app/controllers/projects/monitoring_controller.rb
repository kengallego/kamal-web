class Projects::MonitoringController < Projects::BaseController
  def show
    @history = @project.server_metrics.recent.order(:collected_at).group_by(&:host)
    @hosts = (@project.hosts + @history.keys).uniq
  end

  # Collects a fresh sample from every host right away.
  def create
    if @project.ssh_keys.empty?
      redirect_to project_monitoring_path(@project), alert: "Add an SSH key to the project to collect metrics."
    else
      @project.hosts.each { |host| ServerProbe.new(@project, host).collect }
      redirect_to project_monitoring_path(@project), notice: "Metrics refreshed."
    end
  end
end
