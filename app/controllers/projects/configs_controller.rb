class Projects::ConfigsController < Projects::BaseController
  before_action :set_destination

  def show
    @config = @project.config_for(@destination)
  end
end
