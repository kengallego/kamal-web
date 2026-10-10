# Read-only wallboard for a TV or a status page, reachable with a secret URL.
# It updates live: deploys, metrics and project changes broadcast a refresh on
# STREAM, and the page morphs in the new state.
class StatusBoardsController < ApplicationController
  STREAM = "status_board".freeze
  COOKIE = :kamal_web_status_board

  allow_unauthenticated_access
  skip_before_action :require_allowed_ip
  layout "status_board"

  def show
    setting = Setting.instance
    return head :not_found unless setting.status_board_viewer?(params[:token].to_s)

    # Lets the board's WebSocket connect without a session.
    cookies.signed[COOKIE] = { value: params[:token].to_s, httponly: true, same_site: :lax }
    @projects = Project.ordered
    @latest_metrics = ServerMetric.where(id: ServerMetric.recent.group(:project_id, :host).select("MAX(id)")).group_by(&:project_id)
  end
end
