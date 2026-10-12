class DashboardController < ApplicationController
  def show
    @projects = Project.ordered.includes(:command_runs)
    @recent_runs = CommandRun.includes(:project).latest_first.limit(15)
    @alerts = Alert.active.includes(:project).latest_first
    @latest_metrics = ServerMetric.where(id: ServerMetric.recent.group(:project_id, :host).select("MAX(id)")).group_by(&:project_id)
  end
end
