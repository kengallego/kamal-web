# Lazily loaded next to the Deploy button: reading the lock and the running
# version takes an SSH round trip.
class Projects::DeployPreviewsController < Projects::BaseController
  before_action :set_destination

  def show
    @preview = DeployPreview.new(@project, @destination).call
  rescue RemoteShell::Error => error
    @error = error.message
  ensure
    render partial: "projects/deploy_previews/preview"
  end
end
