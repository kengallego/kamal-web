class Projects::ProxiesController < Projects::BaseController
  before_action :set_destination

  def show
    @config = @project.config_for(@destination)
    @hosts = @config.roles.values.flatten.uniq
    @host = @hosts.include?(params[:host]) ? params[:host] : @hosts.first

    # The page renders immediately; the turbo frame then requests the data.
    return unless turbo_frame_request? && @host

    inspector = ProxyInspector.new(@project, @host)
    @routes = inspector.routes
    @requests = inspector.requests
    @requests = @requests.select { |request| request.status_class == params[:status] } if params[:status].present?
    render partial: "projects/proxies/data"
  rescue RemoteShell::Error => error
    render partial: "projects/proxies/error", locals: { message: error.message }
  end
end
