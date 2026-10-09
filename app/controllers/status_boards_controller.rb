# Read-only wallboard for a TV or a status page, reachable with a secret URL.
class StatusBoardsController < ApplicationController
  allow_unauthenticated_access
  layout "status_board"

  def show
    setting = Setting.instance
    unless setting.status_board_enabled? && ActiveSupport::SecurityUtils.secure_compare(setting.status_board_token, params[:token].to_s)
      return head :not_found
    end

    @projects = Project.ordered
    @latest_metrics = ServerMetric.where(id: ServerMetric.recent.group(:project_id, :host).select("MAX(id)")).group_by(&:project_id)
  end
end
