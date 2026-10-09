class Projects::CommandRunsController < Projects::BaseController
  before_action :set_run, only: %i[ show cancel ]

  def index
    @runs = @project.command_runs.includes(:user).latest_first
    @runs = @runs.where(destination: params[:destination].presence) if params.key?(:destination)
    @runs = @runs.where(kind: params[:kind]) if params[:kind].present?
    @runs = @runs.limit(100)
  end

  def show
  end

  def create
    command = CommandCatalog.find(params.require(:kind))
    return require_role(command.role) unless current_user.can?(command.role)

    run = @project.command_runs.new(
      kind: command.key,
      destination: params[:destination],
      options: params.fetch(:options, {}).permit(*command.fields.map(&:name)).to_h,
      user: current_user
    )

    if run.save
      redirect_to project_command_run_path(@project, run)
    else
      redirect_back fallback_location: project_commands_path(@project), alert: run.errors.full_messages.to_sentence
    end
  rescue KeyError
    redirect_back fallback_location: project_commands_path(@project), alert: "Unknown command."
  end

  def cancel
    if current_user.can?(@run.command.role) || @run.user == current_user
      @run.cancel!
      redirect_to project_command_run_path(@project, @run), notice: "Command canceled."
    else
      require_role(@run.command.role)
    end
  end

  private
    def set_run
      @run = @project.command_runs.find(params[:id])
    end
end
