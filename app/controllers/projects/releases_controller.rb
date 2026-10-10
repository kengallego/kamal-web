# Lazily loaded into the project overview: listing the versions takes an SSH
# round trip.
class Projects::ReleasesController < Projects::BaseController
  before_action :set_destination

  def show
    @releases = ServerReleases.new(@project, @destination).call
  rescue RemoteShell::Error => error
    @error = error.message
  ensure
    render partial: "projects/releases/releases"
  end
end
