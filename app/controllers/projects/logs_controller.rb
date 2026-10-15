# App logs, run as soon as the tab opens: the options on the left, the output
# streaming on the right. Each run replaces the previous one in place.
class Projects::LogsController < Projects::BaseController
  DEFAULTS = { "host" => "", "container_id" => "", "lines" => "200", "grep" => "", "follow" => "1" }.freeze

  before_action :set_destination

  def show
    @config = @project.config_for(@destination)
    @options = DEFAULTS.merge(log_options)
  end

  def create
    replace_previous_run
    @run = @project.command_runs.new(kind: "app_logs", destination: @destination, options: DEFAULTS.merge(log_options))

    if @run.save
      render partial: "projects/logs/output", locals: { run: @run }
    else
      render partial: "projects/logs/output", locals: { run: nil, error: @run.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private
    def log_options
      params.fetch(:options, {}).permit(*DEFAULTS.keys).to_h
    end

    # A followed run would otherwise keep streaming for up to 30 minutes.
    def replace_previous_run
      @project.command_runs.active.find_by(id: params[:replace], kind: "app_logs")&.cancel!
    end
end
