class Projects::ConsoleSessionsController < Projects::BaseController
  before_action :set_destination, only: :index

  def index
    @config = @project.config_for(@destination)
    @sessions = @project.console_sessions.latest_first.limit(50)
  end

  def create
    session = @project.console_sessions.new(params.permit(:kind, :destination, :host))

    if session.save
      redirect_to project_console_session_path(@project, session)
    else
      redirect_to project_console_sessions_path(@project, destination: session.destination), alert: session.errors.full_messages.to_sentence
    end
  end

  def show
    @session = @project.console_sessions.find(params[:id])
  end
end
