class Projects::CommandRunsController < Projects::BaseController
  before_action :set_run, only: %i[ show cancel ]

  def index
    @runs = @project.command_runs.latest_first
    @runs = @runs.where(destination: params[:destination].presence) if params.key?(:destination)
    @runs = @runs.where(kind: params[:kind]) if params[:kind].present?
    @runs = @runs.limit(100)
  end

  def show
  end

  def create
    command = CommandCatalog.find(params.require(:kind))
    run = @project.command_runs.new(
      kind: command.key,
      destination: params[:destination],
      confirmation: params[:confirmation],
      options: params.fetch(:options, {}).permit(*command.fields.map(&:name)).to_h
    )

    if run.save
      redirect_to project_command_run_path(@project, run)
    else
      redirect_back fallback_location: project_commands_path(@project), alert: run.errors.full_messages.to_sentence
    end
  rescue KeyError
    redirect_back fallback_location: project_commands_path(@project), alert: t("flash.command_runs.unknown")
  end

  def cancel
    @run.cancel!
    redirect_to project_command_run_path(@project, @run), notice: t("flash.command_runs.canceled")
  end

  private
    def set_run
      @run = @project.command_runs.find(params[:id])
    end
end
