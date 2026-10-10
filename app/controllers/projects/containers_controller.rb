# Polled by the command run page while a command that changes servers runs.
class Projects::ContainersController < Projects::BaseController
  before_action :set_destination

  def show
    @run = @project.command_runs.find_by(id: params[:run_id])
    @containers, @errors = ServiceContainers.new(@project, @destination).call
    render partial: "projects/containers/containers"
  end
end
