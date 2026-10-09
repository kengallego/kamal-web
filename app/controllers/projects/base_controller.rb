class Projects::BaseController < ApplicationController
  before_action :set_project

  private
    def set_project
      @project = Project.find(params[:project_id])
    end

    def set_destination
      requested = params[:destination].presence
      @destination = @project.destinations.include?(requested) ? requested : @project.destinations.first
    end
end
