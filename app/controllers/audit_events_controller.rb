# The Activity page: who changed what, newest first, 100 at a time.
class AuditEventsController < ApplicationController
  PER_PAGE = 100

  def index
    scope = AuditEvent.latest_first.includes(:project)
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
    scope = scope.where(project_id: params[:project_id]) if params[:project_id].present?
    scope = scope.where(id: ...params[:before].to_i) if params[:before].present?
    @events = scope.limit(PER_PAGE + 1).to_a
    @older = @events.pop.then { @events.last } if @events.size > PER_PAGE
    @users = User.ordered
  end
end
